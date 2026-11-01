#include <stdint.h>
#include <stddef.h>

#define MASK(x, y, z) (((x) >> (y)) & ((1 << (z)) - 1))

extern uintptr_t* framebuffer_address;
extern uintptr_t* base_address;
extern unsigned int display_width;
extern unsigned int display_height;

typedef uintptr_t (*get_env_uint_t)(char* env);
extern get_env_uint_t _get_env_uint;
#define get_env_uint _get_env_uint

typedef char* (*get_env_t)(char* env);
extern get_env_t _get_env;
#define get_env _get_env

typedef int (*printf_t)(const char *fmt, ...) __attribute__((format(__printf, 1, 2)));
extern printf_t _printf;
#define __printf _printf

get_env_uint_t find_get_env_uint();
uintptr_t* find_base_address();
uintptr_t* find_framebuffer_address();
get_env_t find_get_env();
uint32_t find_display_width();
uint32_t find_display_height();
printf_t find_printf();

/*
int find_version();
*/
