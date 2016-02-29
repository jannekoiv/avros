#include "avros_asm.h"

void init(void*);
void lock();
void unlock();
void schedule();
unsigned long get_time();
char create(void*);
void exit();
char get_id();
unsigned int sleep(unsigned int time);
char signal(char id, unsigned char sig);
char sem_wait(unsigned char sem, unsigned char trywait);
char sem_post(unsigned char sem, unsigned char cnt);
char sem_get(unsigned char sem);
char mtx_lock(unsigned char mtx, unsigned char trylock);
char mtx_unlock(unsigned char mtx);

