#include <stdint.h>
uint32_t argus_adapter_address(uint64_t luid, const char *ip, uint8_t prefix);
uint32_t argus_adapter_route(uint64_t luid, const char *ip);
uint32_t argus_adapter_neighbor(uint64_t luid, const char *ip);
void argus_adapter_read(uint8_t *dest, const void *src, uint32_t n);
void argus_adapter_write(void *dest, const uint8_t *src, uint32_t n);
void argus_adapter_move(uint8_t *dest, uint32_t dest_off, const uint8_t *src, uint32_t n);
