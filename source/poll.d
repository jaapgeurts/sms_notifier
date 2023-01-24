/* Compatibility definitions for System V `poll' interface.
   Copyright (C) 1994-2022 Free Software Foundation, Inc.
   This file is part of the GNU C Library.

   The GNU C Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   The GNU C Library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with the GNU C Library; if not, see
   <https://www.gnu.org/licenses/>.  */

import core.stdc.config;

extern (C):


/* Event types that can be polled for.  These bits may be set in `events'
   to indicate the interesting event types; they will appear in `revents'
   to indicate the status of the file descriptor.  */
enum POLLIN = 0x001; /* There is data to read.  */
enum POLLPRI = 0x002; /* There is urgent data to read.  */
enum POLLOUT = 0x004; /* Writing now will not block.  */

/* These values are defined in XPG4.2.  */
/* Normal data may be read.  */
/* Priority data may be read.  */
/* Writing now will not block.  */
/* Priority data may be written.  */

/* These are extensions for Linux.  */

/* Event types always implicitly polled for.  These bits need not be set in
   `events', but they will appear in `revents' to indicate the status of
   the file descriptor.  */
enum POLLERR = 0x008; /* Error condition.  */
enum POLLHUP = 0x010; /* Hung up.  */
enum POLLNVAL = 0x020; /* Invalid polling request.  */


enum _SYS_POLL_H = 1;

/* Get the platform dependent bits of `poll'.  */

/* Type used for the number of file descriptors.  */
alias nfds_t = c_ulong;

/* Data structure describing a polling request.  */
struct pollfd
{
    int fd; /* File descriptor to poll.  */
    short events; /* Types of events poller cares about.  */
    short revents; /* Types of events that actually occurred.  */
}

/* Poll the file descriptors described by the NFDS structures starting at
   FDS.  If TIMEOUT is nonzero and not -1, allow TIMEOUT milliseconds for
   an event to occur; if TIMEOUT is -1, block until an event occurs.
   Returns the number of file descriptors with events, zero if timed out,
   or -1 for errors.

   This function is a cancellation point and therefore not marked with
   __THROW.  */
int poll (pollfd* __fds, nfds_t __nfds, int __timeout);

/* Like poll, but before waiting the threads signal mask is replaced
   with that specified in the fourth parameter.  For better usability,
   the timeout value is specified using a TIMESPEC object.

   This function is a cancellation point and therefore not marked with
   __THROW.  */

/* Define some inlines helping to catch common problems.  */

/* sys/poll.h */
