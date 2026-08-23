#include "board.h"

// Four words spaced by the 4 KiB cache capacity all map to one set. This
// thrashes direct-mapped and 2-way caches; a 4-way cache can retain all four.
//
// Run with:
//   make board-sim BOARD=sim APP=examples/apps/cache_conflict_4 MEM_BYTES=32768

enum {
  Iterations = 256,
  WordsPerCache = 4096 / sizeof(uint32_t),
};

static volatile uint32_t data[3 * WordsPerCache + 1] __attribute__((aligned(4096))) = {
    [0] = 1u,
    [WordsPerCache] = 3u,
    [2 * WordsPerCache] = 5u,
    [3 * WordsPerCache] = 7u,
};

int main(void) {
  uint32_t sum = 0;

  for (uint32_t iteration = 0; iteration < Iterations; iteration++) {
    sum += data[0];
    sum += data[WordsPerCache];
    sum += data[2 * WordsPerCache];
    sum += data[3 * WordsPerCache];
  }

  uint32_t errors = sum == (Iterations << 4) ? 0u : 1u;
  uart_putc(errors == 0u ? 'P' : 'F');
  uart_putc('\n');
  halt(errors);
  return 0;
}
