global start
extern long_mode_start

section .text
bits 32
start:
    ; move address of top of stack to esp as 
    ; there is currently no frames in the stack
    mov esp, stack_top

    ; switch cpu to long mode (64b mode)

    ; make sure we're in multiboot
    call check_multiboot
    ; fetch cpu info
    call check_cpuid
    ; check if we're already in long mode
    call check_long_mode

    ; set pagging as required
    call setup_page_tables
    call enable_paging

    lgdt [gdt64.pointer]
    jmp gdt64.code_segment:long_mode_start



    hlt

check_multiboot:
    cmp eax, 0x36d76289 ; multiboot magic value
    jne .no_multiboot
    ret

.no_multiboot:
    mov al, "M" ; add "M" error code (multiboot)
    jmp error

check_cpuid:
    ; try and flip the id bit from the register
    ; if we can flip it, cpuid is available
    pushfd
    pop eax
    mov ecx, eax ; store original bit value
    xor eax, 1 << 21 ; flip bit 21
    push eax ; push back value on stack
    popfd
    pushfd
    pop eax
    push ecx
    popfd
    cmp eax, ecx ; compare if value was flipped
    je .no_cpuid
    ret

.no_cpuid:
    mov al, "C" ; store "C" for cpuid in error
    jmp error

check_long_mode:
    mov eax, 0x80000000
    ; when cpuid sees the magic value in eax,
    ; it will store a value back into eax which
    ; will be greater than 0x80000000 if processor
    ; supports extended processor info
    cpuid 
    cmp eax, 0x80000001
    jb .no_long_mode; not supported thus long mode not supported

    mov eax, 0x80000001
    ; this time cpuid will store a value in edx
    ; if lm bit is set, cpu supports long mode
    cpuid 
    test edx, 1 << 29 ; long mode is at bit 29
    jz .no_long_mode
    ret

.no_long_mode:
    mov al, "L" ; store "L" error code for long mode

setup_page_tables:
    ; map physical address to virtual address
    ; identity map the first one gb of pages
    mov eax, page_table_l3
    or eax, 0b11 ; enable present and writable flag
    mov [page_table_l4], eax ; add first entry to level3 table

    ; add
    mov eax, page_table_l2
    or eax, 0b11 ; enable present and writable flag
    mov [page_table_l3], eax ; add first entry to level2 table

    ; instead of creating level 1 table
    ; we create a "huge table" of 2mb each which
    ; level 2 will point to phys mem

    mov ecx, 0 ; counter
.loop:

    ; map 2mb page
    mov eax, 0x200000 ; 2MiB
    mul ecx
    or eax, 0b10000011 ; present, writable, huge page
    mov [page_table_l2 + ecx * 8], eax

    inc ecx ; incremeter counter
    cmp ecx, 512 ; check if the whole table is mapped
    jne .loop ; if not, continue

    ret

enable_paging:
    ; pass page table location to cpu
    mov eax, page_table_l4
    mov cr3, eax

    ; enable PEA
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax
    
    ; enable long mode
    mov ecx, 0xC0000080
    rdmsr ; read module specific register
    or eax, 1 << 8
    wrmsr ; write  to model specific register

    ; enable paging
    mov eax, cr0
    or eax, 1 << 31 ; long mode bit is num 31
    mov cr0, eax

    ret



error:
; print "ERR: X" where X is the error code
    mov dword [0xb8000], 0x4f524f45
    mov dword [0xb8004], 0x4f3a4f52
    mov dword [0xb8008], 0x4f204f20
    mov byte [0xb800a], al ; display error code that's stored in al register
    hlt

section .bss
align 4096
page_table_l4:
    resb 4096
page_table_l3:
    resb 4096
page_table_l2:
    resb 4096

stack_bottom:
    resb 4096 * 4
stack_top:

section .rodata
gdt64:
    ; as we are currently in 32 compat submode, we need to actually switch
    ; to 64b mode. For this, we need to create global descriptor table
    dq 0 ; zero entry
.code_segment: equ $ - gdt64
    ; required code segment. exec flag,
    ; enable executable flag
    ; enable descriptor type for data segments
    ; enable present flag
    ; enable 64b flag
    dq (1 << 43) | (1 << 44) | (1 << 47) | (1 << 53)
.pointer:
    dw $ - gdt64 - 1 
    dq gdt64

