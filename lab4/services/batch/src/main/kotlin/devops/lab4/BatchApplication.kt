package devops.lab4

fun main() {
    val memoryMb = System.getenv("MEMORY_MB")?.toInt() ?: 128
    val cpuWorkers = System.getenv("CPU_WORKERS")?.toInt() ?: 1

    val memory = ByteArray(memoryMb * 1024 * 1024)
    for (i in memory.indices step 4096) {
        memory[i] = 1
    }

    repeat(cpuWorkers) {
        Thread {
            var value = 0L
            while (true) {
                value = value * 1_664_525 + 1_013_904_223
            }
        }.start()
    }

    println("batch started: memoryMb=$memoryMb, cpuWorkers=$cpuWorkers")

    while (true) {
        memory[0]++
        Thread.sleep(10_000)
        println("batch is still running")
    }
}
