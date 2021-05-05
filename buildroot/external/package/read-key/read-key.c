/*
 * Compilation: gcc -static -O3 -Wall -o read-key read-key.c -lpthread && objcopy --strip-unneeded read-key
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <pthread.h>
#include <fcntl.h>
#include <unistd.h>
#include <linux/input.h>

#define DEBUG 0
#define EXIT_ON_KEY_DOWN 0
#define MAX_LINE_LEN 200
#define MAX_KBD_COUNT 12

void *wait_for_event(void *event_dev_num);
int extract_numbers(char *string);

int main(int argc, char *argv[])
{
	FILE *fp;
	char *input_devs = "/proc/bus/input/devices";
	char line[MAX_LINE_LEN];
	int device_nums[MAX_KBD_COUNT];
	int device_num, i = 0, thread_count;

	fp = fopen(input_devs, "r");
	if (fp == NULL) {
		fprintf(stderr, "error: couldn't open %s for reading!\n", input_devs);
		exit(EXIT_FAILURE);
	}

	while(fgets(line, MAX_LINE_LEN, fp)) {
		/* TODO: Ignore TS with kbd handlers! */
		if (line[0] != '\n' && strstr(line, "Handlers=") != NULL &&
		    strstr(line, "kbd") != NULL) {
			device_num = extract_numbers(line);
			if (i == MAX_KBD_COUNT) {
				fprintf(stderr, "warn: device count exceeded MAX_KBD_COUNT (%d), ignoring event%d...\n", MAX_KBD_COUNT, device_num);
				break;
			}
			device_nums[i] = device_num;
			i++;
		}
	}
	fclose(fp);

	thread_count = i;
	if (thread_count < 1) {
		fprintf(stderr, "error: no kbd input devices detected!\n");
		sleep(1);
		exit(EXIT_FAILURE);
	}

	pthread_t thread_ids[thread_count];
	for (i = 0; i < thread_count; i++) {
#if DEBUG
		printf("thread %d -> watching /dev/input/event%d...\n", i+1, device_nums[i]);
#endif
		pthread_create(&thread_ids[i], NULL , wait_for_event, &device_nums[i]);
	}
	pause(); // wait for one of the threads to call exit()
	return 0;
}

void *wait_for_event(void *event_dev_num_p)
{
	int fd, event_dev_num = *(int*)event_dev_num_p;
	char ev_dev[MAX_LINE_LEN];
	struct input_event ev;

	snprintf(ev_dev, MAX_LINE_LEN, "/dev/input/event%d", event_dev_num);
	fd = open(ev_dev, O_RDONLY);
	if (fd < 0) {
		fprintf(stderr, "error: couldn't read %s!\n", ev_dev);
		return NULL;
	}

	for (int i = 0; i < 2000; i++) {
		read(fd, &ev, sizeof(ev));
#if DEBUG
		printf("event -> type: %d, code: %d, value: %d\n", ev.type, ev.code, ev.value);
#endif
		if (ev.type == 1 && ev.value == EXIT_ON_KEY_DOWN) {
			printf("%d\n", ev.code);
			exit(0);
		}
	}
	return NULL;
}

int extract_numbers(char *string)
{
	char *p = string;
	char result_str[MAX_LINE_LEN] = "";
	int i = 0;
	int result;

	while (*p) {
		if (isdigit(*p))
			result_str[i++] = (char) *p;
		p++;
	}

	sscanf(result_str, "%d", &result);
	return result;
}
