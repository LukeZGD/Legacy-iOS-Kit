#ifndef memory_h
#define memory_h

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <mach/mach.h>
#include <CoreFoundation/CoreFoundation.h>

#define mem_barrier() {asm volatile ("dmb sy");}
#define mem_sync() {asm volatile ("dsb sy");}

extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_offset_t, int, mem_entry_name_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);
extern kern_return_t mach_vm_deallocate(vm_map_t, mach_vm_address_t, mach_vm_size_t);
extern kern_return_t mach_vm_allocate(vm_map_t, mach_vm_address_t *, mach_vm_size_t, int);
extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);
extern kern_return_t mach_vm_write(vm_map_t, mach_vm_address_t, vm_offset_t, mach_msg_type_number_t);
extern kern_return_t mach_vm_msync(vm_map_t, mach_vm_address_t, mach_vm_size_t, vm_sync_t);
extern kern_return_t task_get_special_port(task_t, int, mach_port_t *);

uint8_t *map_data(uint32_t pa, uint32_t size, vm_prot_t prot);
uint8_t *map_relative_data(uint32_t offset, uint32_t size, vm_prot_t prot);
void unmap_data(uint8_t *addr, uint32_t size);
void sync_mapping(uint8_t *addr, uint32_t size);
void physread_buf(uint32_t addr, void *data, uint32_t size);
void physwrite_buf(uint32_t addr, void *data, uint32_t size);
uint32_t physread32(uint32_t addr);
uint16_t physread16(uint32_t addr);
uint8_t physread8(uint32_t addr);
void physwrite32(uint32_t addr, uint32_t data);
void physwrite16(uint32_t addr, uint16_t data);
void physwrite8(uint32_t addr, uint8_t data);
void kread_buf(uint32_t addr, void *data, uint32_t size);
void kwrite_buf(uint32_t addr, void *data, uint32_t size);
void kwrite_buf_exec(uint32_t addr, void *data, uint32_t size);
uint32_t kread32(uint32_t addr);
uint16_t kread16(uint32_t addr);
uint8_t kread8(uint32_t addr);
void kwrite32(uint32_t addr, uint32_t data);
void kwrite16(uint32_t addr, uint16_t data);
void kwrite8(uint32_t addr, uint8_t data);
void kwrite32_exec(uint32_t addr, uint32_t data);
void kwrite16_exec(uint32_t addr, uint16_t data);
void kwrite8_exec(uint32_t addr, uint8_t data);
uint32_t kalloc(size_t size);
void kfree(uint32_t addr, size_t size);
uint32_t kvtophys(uint32_t va);

#endif /* memory_h */
