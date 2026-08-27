#include "board.h"

// Fixed-work performance workload. Keep this free of peripheral polling so
// memory latency cannot change the dynamic instruction count.
int main(void) {
  volatile uint32_t values[16];
  uint32_t checksum = 0;

  for (uint32_t i = 0; i < 16u; i++) {
    values[i] = (i << 16) ^ (i * 17u) ^ 0x5a5a5a5au;
  }

  for (uint32_t pass = 0; pass < 8u; pass++) {
    for (uint32_t i = 0; i < 16u; i++) {
      uint32_t value = values[i];
      value = (value << 1) | (value >> 31);
      value ^= pass + i;
      values[i] = value;
      checksum += value;
    }
  }

  halt(checksum == 0u);
  return 0;
}
