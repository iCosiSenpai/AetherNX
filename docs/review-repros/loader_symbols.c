#include <stdio.h>
#include <stdlib.h>
static void *review_calloc(size_t,size_t);
#define calloc review_calloc
#define main original_symbols_fixture_main
#include "../../dm/host/tests/t_symbols.c"
#undef main
#undef calloc
static void *review_calloc(size_t n,size_t size) {
    if(n>1048576/size) { printf("Two-symbol dynamic table requested %zu bytes for the symbol index\n",n*size); fflush(stdout); _exit(0); }
    return calloc(n,size);
}
static void timed_out(int sig) { (void)sig; const char msg[]="parse_dynamic did not return for a bounded two-symbol dynamic table\n"; write(1,msg,sizeof(msg)-1); _exit(0); }
int main(void) {
    struct rlimit limit={0,0};setrlimit(RLIMIT_CORE,&limit);
    uint8_t image[4096]={0}; module_t module={0};
    module.base=image; module.size=sizeof image; strcpy(module.name,"synthetic");
    *(uint32_t*)(image+4)=0x20; memcpy(image+0x20,"MOD0",4); *(int32_t*)(image+0x24)=0x20;
    Elf64_Dyn *dyn=(Elf64_Dyn*)(image+0x40);
    dyn[0]=(Elf64_Dyn){.d_tag=DT_SYMTAB,.d_un.d_ptr=0x200};
    dyn[1]=(Elf64_Dyn){.d_tag=DT_STRTAB,.d_un.d_ptr=0x100};
    dyn[2]=(Elf64_Dyn){.d_tag=4 /* DT_HASH */,.d_un.d_ptr=0x180};
    dyn[3]=(Elf64_Dyn){.d_tag=0};
    memcpy(image+0x100,"\0symbol\0",8);
    uint32_t *hash=(uint32_t*)(image+0x180);hash[0]=1;hash[1]=2;hash[2]=1;
    Elf64_Sym *symbols=(Elf64_Sym*)(image+0x200);
    symbols[1].st_name=1; symbols[1].st_shndx=1; symbols[1].st_value=0x300;
    signal(SIGALRM,timed_out); alarm(1);
    parse_dynamic(&module);
    fprintf(stderr,"parse_dynamic returned: symbols=%u\n",module.nsym); return 1;
}
