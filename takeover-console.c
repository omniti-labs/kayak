/*
 * This file and its contents are supplied under the terms of the
 * Common Development and Distribution License ("CDDL"), version 1.0.
 * You may only use this file in accordance with the terms of version
 * 1.0 of the CDDL.
 *
 * A full copy of the text of the CDDL should have accompanied this
 * source.  A copy of the CDDL is also available via the Internet at
 * http://www.illumos.org/license/CDDL.
 */

/*
 * Copyright 2017 OmniTI Computer Consulting, Inc. All rights reserved.
 */

#include <fcntl.h>
#include <unistd.h>

int
main(int argc, char *argv[])
{
	/* Wrest control of /dev/console, and exec the commands after 0, 0. */
	int fd;

	(void) setpgrp();
	(void) close(0);
	(void) close(1);
	(void) close(2);
	fd = open("/dev/console", O_RDWR, 0);
	if (fd == 0) {
		(void) fcntl(0, F_DUP2FD, 1);
		(void) fcntl(0, F_DUP2FD, 2);
	}
	execv(argv[1], &(argv[2]));
}
