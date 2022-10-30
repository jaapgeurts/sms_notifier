module logging;

import std.stdio;
import std.functional : partial;
import std.conv : to;

enum LogLevel {
    DEBUG,
    INFO,
    WARNING,
    ERROR,
    NONE
}

LogLevel loggingLevel = LogLevel.NONE;

void log(T...)(LogLevel level, T args) {
    if (level >= loggingLevel) {
        writeln(to!string(level), ": ", args);
        stdout.flush();
        stderr.flush();
    }
}

alias logdebug = partial!(log, LogLevel.DEBUG);
alias loginfo = partial!(log, LogLevel.INFO);
alias logwarn = partial!(log, LogLevel.WARNING);
alias logerror = partial!(log, LogLevel.ERROR);

void setDefaultLoggingLevel(LogLevel level) {
    loggingLevel = level;
}
