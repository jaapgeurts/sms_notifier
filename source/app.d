import std.getopt;
import std.concurrency;
import std.container;
import std.algorithm.searching : find, canFind;
import std.range : take;

import core.stdc.errno;
import core.stdc.string : strerror;

import poll;
import modem;
import notifications;
import logging;

import ddbus;
import ddbus.c_lib;

struct WatchConn {
    DBusWatch* watch;
    DBusConnection* connection;

    bool opEquals()(auto ref const WatchConn other) const {
        return watch == other.watch && connection == other.connection;
    }
}

Array!(WatchConn) watches;

void main(string[] args) {

    LogLevel logLevel = LogLevel.NONE;

    try {
        // dfmt off
        auto helpInformation = getopt(args,
            std.getopt.config.passThrough,
            "log|l", "Logging Level [DEBUG,INFO,WARN,ERROR,NONE*]\t* default", &logLevel,
            );
        // dfmt on

        if (helpInformation.helpWanted) {
            defaultGetoptPrinter("sms_notifier. ", helpInformation.options);
            return;
        }
    }
    catch (Exception e) {
        logerror(e.msg);
        return;
    }

    setDefaultLoggingLevel(logLevel);

    logdebug("Starting");

    // Don't lock any data structures so we can call from multiple threads
    dbus_threads_init_default();

    Connection sysbus = connectToBus(DBusBusType.DBUS_BUS_SYSTEM);
    Connection sessbus = connectToBus();
    // closing these connections is not necessary

    // TODO: disable exit on disconnect and try to reconnect
    // Check what happens when the modem disappears

    // setup dbus watch functions
    dbus_connection_set_watch_functions(sysbus.conn, &onAddWatch, &onRemoveWatch, &onWatchToggled, sysbus.conn, &dbus_free);
    dbus_connection_set_watch_functions(sessbus.conn, &onAddWatch, &onRemoveWatch, &onWatchToggled, sessbus.conn, &dbus_free);

    // setup callbacks
    DBusClientModemProc(sysbus, logLevel);
    DBusClientNotificationsProc(sessbus, logLevel);

    while (true) {
        // Wait for activity on the connections
        int nfds = 0;
        pollfd[] fds = new pollfd[watches.length];
        foreach (watch; watches) {
            if (dbus_watch_get_enabled(watch.watch)) {
                fds[nfds].fd = dbus_watch_get_unix_fd(watch.watch);
                fds[nfds].events = cast(short) dbus_watch_get_flags(watch.watch);
                nfds++;
            }
        }
        if (poll.poll(fds.ptr, nfds, -1) == -1) {
            logerror("Error in poll() on dbus fd's: ", strerror(errno));
        }
        // Check each of the fildes and handle messages
        for (int i = 0; i < nfds; i++) {
            auto pfd = fds[i];
            short flags = cast(short) dbus_watch_get_flags(watches[i].watch);
            if ((pfd.revents & flags) > 0) {
                logdebug("Handling watch");
                dbus_watch_handle(watches[i].watch, flags);
                while (dbus_connection_dispatch(
                        watches[i].connection) == DBusDispatchStatus.DBUS_DISPATCH_DATA_REMAINS) {
                }
            }
        }
    }
}

extern (C) {
    uint onAddWatch(DBusWatch* watch, void* data) {
        if (dbus_watch_get_enabled(watch)) {
            logdebug("Adding dbus watch");
            WatchConn watchCon = {
                watch: watch,
                connection: cast(DBusConnection*) data
            };
            watches.insertBack(watchCon);
        }
        return 1;
    }

    void onRemoveWatch(DBusWatch* watch, void* data) {
        logdebug("removing dbus watch");
        WatchConn watchCon = {
            watch: watch,
            connection: cast(DBusConnection*) data
        };
        auto range = watches[];
        watches.linearRemove(range.find(watchCon).take(1));
    }

    void onWatchToggled(DBusWatch* watch, void* data) {
        logdebug("dbus watch enable toggled");
        WatchConn watchCon = {
            watch: watch,
            connection: cast(DBusConnection*) data
        };
        auto range = watches[];
        if (range.canFind(watchCon))
            watches.linearRemove(range.find(watchCon).take(1));
        else
            watches.insertBack(watchCon);
    }

}
