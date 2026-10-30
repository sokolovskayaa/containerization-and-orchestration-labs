public final class Batch {
    private static volatile long sink;

    public static void main(String[] args) throws InterruptedException {
        int memoryMb = Integer.parseInt(System.getenv().getOrDefault("MEMORY_MB", "128"));
        int workers = Integer.parseInt(System.getenv().getOrDefault("CPU_WORKERS", "1"));
        if (memoryMb < 1 || workers < 0) {
            throw new IllegalArgumentException("MEMORY_MB must be positive; CPU_WORKERS must be nonnegative");
        }
        byte[] memory = new byte[Math.multiplyExact(memoryMb, 1024 * 1024)];
        for (int i = 0; i < memory.length; i += 4096) memory[i] = 1;
        for (int i = 0; i < workers; i++) {
            new Thread(() -> {
                long value = 1;
                while (true) {
                    for (int n = 0; n < 100_000; n++) value = value * 1_664_525 + 1_013_904_223;
                    sink = value;
                }
            }, "cpu-" + i).start();
        }
        System.out.printf("batch started: memoryMb=%d, cpuWorkers=%d%n", memoryMb, workers);
        while (true) {
            memory[0]++;
            Thread.sleep(10_000);
            System.out.println("batch is still running; memory=" + memory.length);
        }
    }
}
