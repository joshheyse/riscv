#include "board.h"

// A streaming traversal provides a control case: the four accessed lines map
// to different sets, so greater associativity should not reduce its misses.
// It performs the same number of timed-loop loads as cache_conflict_4.
//
// Run with:
//   make board-sim BOARD=sim APP=examples/apps/cache_sequential MEM_BYTES=32768

enum {
  Iterations = 256,
  WordsPerLine = 32 / sizeof(uint32_t),
};

static volatile uint32_t data[4 * WordsPerLine] __attribute__((aligned(32))) = {
    [0 * WordsPerLine] = 1u,
    [1 * WordsPerLine] = 3u,
    [2 * WordsPerLine] = 5u,
    [3 * WordsPerLine] = 7u,
};

int main(void) {
  uint32_t sum = 0;

  for (uint32_t iteration = 0; iteration < Iterations; iteration++) {
    sum += data[0 * WordsPerLine];
    sum += data[1 * WordsPerLine];
    sum += data[2 * WordsPerLine];
    sum += data[3 * WordsPerLine];
  }

  uint32_t errors = sum == (Iterations << 4) ? 0u : 1u;
  uart_putc(errors == 0u ? 'P' : 'F');
  uart_putc('\n');
  halt(errors);
  return 0;
}
