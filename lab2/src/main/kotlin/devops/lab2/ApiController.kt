package devops.lab2

import io.opentelemetry.api.OpenTelemetry
import io.opentelemetry.api.trace.Span
import io.opentelemetry.api.trace.StatusCode
import io.micrometer.core.instrument.Counter
import io.micrometer.core.instrument.Timer
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.util.concurrent.TimeUnit
import kotlin.random.Random

@RestController
@RequestMapping(produces = [MediaType.TEXT_PLAIN_VALUE])
class ApiController(
    private val meterRegistry: PrometheusMeterRegistry,
    @Value("\${server.port:8080}") private val serverPort: Int,
    private val openTelemetry: OpenTelemetry,
) {
    private val log = LoggerFactory.getLogger(ApiController::class.java)
    private val httpClient = HttpClient.newHttpClient()
    private val tracer = openTelemetry.getTracer("devops.lab2")

    private val requestCounter: Counter = Counter.builder("api_requests_total")
        .description("Total number of HTTP requests handled by the API")
        .register(meterRegistry)

    private val errorCounter: Counter = Counter.builder("api_errors_total")
        .description("Total number of HTTP 5xx responses returned by the API")
        .register(meterRegistry)

    private val responseTimer: Timer = Timer.builder("api_request_duration")
        .description("HTTP request duration")
        .publishPercentiles(0.95)
        .publishPercentileHistogram()
        .register(meterRegistry)

    @GetMapping("/health")
    fun health(): String = "ok"

    @GetMapping("/fail")
    fun fail(): ResponseEntity<String> {
        Span.current().setStatus(StatusCode.ERROR, "intentional failure")
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body("intentional failure")
    }

    @GetMapping("/slow")
    fun slow(): String {
        val span = tracer.spanBuilder("slow-op").startSpan()
        return try {
            span.makeCurrent().use {
                Thread.sleep(Random.nextLong(1_000, 3_001))
            }
            "slow response complete"
        } finally {
            span.end()
        }
    }

    @GetMapping("/load")
    fun load(): String {
        val request = HttpRequest.newBuilder()
            .uri(URI.create("http://localhost:$serverPort/health"))
            .GET()
            .build()

        repeat(25) {
                httpClient.sendAsync(request, HttpResponse.BodyHandlers.discarding())
                .exceptionally { exception ->
                    log.warn("{\"event\":\"load_request_failed\",\"error\":\"{}\"}", exception.message)
                    null
                }
        }
        return "scheduled 25 requests"
    }

    @GetMapping("/metrics", produces = ["text/plain; version=0.0.4; charset=utf-8"])
    fun metrics(): String = meterRegistry.scrape()

    fun recordRequest(status: Int, elapsedNanos: Long, method: String, path: String, traceId: String) {
        requestCounter.increment()
        responseTimer.record(elapsedNanos, TimeUnit.NANOSECONDS)
        if (status >= 500) errorCounter.increment()
        log.info(
            "{\"event\":\"http_request\",\"method\":\"{}\",\"path\":\"{}\",\"status\":{},\"duration_ms\":{},\"trace_id\":\"{}\"}",
            method,
            path,
            status,
            elapsedNanos / 1_000_000,
            traceId,
        )
    }
}
