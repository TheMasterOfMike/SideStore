#ifdef MDC
#ifndef helpers_h
#define helpers_h

char* get_temporary_file_location_paths(void);
void test_nsexpressions(void);
char* setup_temporary_file(void);

void crash_with_xpc_thingy(char* service_name);

#define ROUND_DOWN_PAGE(val) (val & ~(PAGE_SIZE - 1ULL))

#endif /* helpers_h */
#endif /* MDC */
