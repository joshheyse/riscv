#include "board.h"

// The direct-mapped cache has 128 sets and 32-byte lines, so addresses 4 KiB
// apart have the same set index and different tags. A 2-way cache can retain
// both of these words after their compulsory misses.
//
// Run with:
//   make board-sim BOARD=sim APP=examples/apps/cache_conflict_2 MEM_BYTES=32768

enum {
  Iterations = 256,
  WordsPerCache = 4096 / sizeof(uint32_t),
};

static volatile uint32_t data[WordsPerCache + 1] __attribute__((aligned(4096))) = {
    [0] = 1u,
    [WordsPerCache] = 3u,
};

int main(void) {
  uint32_t sum = 0;

  for (uint32_t iteration = 0; iteration < Iterations; iteration++) {
    sum += data[0];
    sum += data[WordsPerCache];
  }

  uint32_t errors = sum == (Iterations << 2) ? 0u : 1u;
  uart_putc(errors == 0u ? 'P' : 'F');
  uart_putc('\n');
  halt(errors);
  return 0;
}
