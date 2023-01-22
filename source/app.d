import std.getopt;
import std.concurrency;

import modem;
import notifications;
import logging;

import ddbus.c_lib;

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

    auto sysbusTid = spawn(&DBusClientModemProc, logLevel);

    auto sessbusTid = spawn(&DBusClientNotificationsProc, logLevel);

}


