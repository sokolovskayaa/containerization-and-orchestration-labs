package devops.lab2

import io.opentelemetry.api.trace.Span
import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter

@Component
class RequestMetricsFilter(
    private val apiController: ApiController,
) : OncePerRequestFilter() {
    override fun shouldNotFilter(request: HttpServletRequest): Boolean =
        request.requestURI == "/metrics"

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val started = System.nanoTime()
        try {
            filterChain.doFilter(request, response)
        } finally {
            val traceId = Span.current().spanContext.takeIf { it.isValid }?.traceId ?: ""
            apiController.recordRequest(
                status = response.status,
                elapsedNanos = System.nanoTime() - started,
                method = request.method,
                path = request.requestURI,
                traceId = traceId,
            )
        }
    }
}
