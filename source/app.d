import std.stdio;
import std.conv;
import std.functional : toDelegate;
import std.regex;
import std.array;
import std.algorithm;
import std.functional : partial;
import std.getopt;

import core.thread;

import ddbus;
import ddbus.c_lib;

import xclipboard;

Connection sessbus;
Connection sysbus;

XClipboard clipboard;

enum LogLevel { DEBUG, INFO, WARNING, ERROR, NONE }

LogLevel loggingLevel = LogLevel.NONE;

// FIXME: bad bad bad
uint[uint] notificationIds;

void log(T...)(LogLevel level, T args) {
    if (level >= loggingLevel) writeln( to!string(level),": ", args);
}

alias logdebug = partial!(log,LogLevel.DEBUG);
alias loginfo = partial!(log,LogLevel.INFO);
alias logwarn = partial!(log,LogLevel.WARNING);
alias logerror = partial!(log,LogLevel.ERROR);


// TODO: move to main. Now it crashes because assignment copies the object
// which involves a construct/destruct cycle. This closes the connection
static this() {
    sysbus = connectToBus(DBusBusType.DBUS_BUS_SYSTEM);
    sessbus = connectToBus();
}

void copyToClipboardClicked(uint id, string action_key) {
    // TODO: check if id is a notification that I sent
    if (id !in notificationIds) {
        logwarn("CopyToClipboard received for non-owned notification");
        return;
    }
    loginfo("copy to clip: Id: ", id, " Signal: " ~ action_key);
    clipboard.copyTo(action_key);
}

void notificationClosed(uint id, uint reason) {
    if (id !in notificationIds) {
        logdebug("Notification closed but not mine. Not taking action.");
        return;
    }
    loginfo("Closed notification: ", id, " reasoncode: ", reason);
    notificationIds.remove(id);
}

void smsReceived(ObjectPath path, bool val) {
    loginfo("Sms received: path: ", path, " received: ", val ? "yes" : "no");
    if (!val) {
        logwarn("Message added locally");
        return;
    }
    logdebug("Message received from radio");
    string text = getSmsMessage(path);
    if (text == null)
        return;
    // find any numbers in the text.
    string[] numbers;
    auto r = regex(r"\d+");
    numbers = matchAll(text, r).map!(m => m.hit).array();

    sendNotification(text, numbers);

}

void sendNotification(string text, string[] copyValues) {

    // Send message

    PathIface dbus_notify = new PathIface(sessbus, "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications", "org.freedesktop.Notifications");
    string[] list; // must have even num elements. even elem = action, odd elem = message to user
    foreach (copyval; copyValues) {
        list ~= copyval;
        list ~= "Copy " ~ copyval;
    }
    Variant!DBusAny[string] map;

    Message msg = dbus_notify.Notify("SMS Received", cast(uint) 0, "mail-message-new-list", "A SMS message was received",
        text, list, map, 10000);
    uint id = msg.to!uint();
    notificationIds[id] = id;
    loginfo("Created notification with id: ", id);
}

string getSmsMessage(ObjectPath path) {

    PathIface dbus_messaging = new PathIface(sysbus, "org.freedesktop.ModemManager1",
        path, "org.freedesktop.DBus.Properties");
    //auto res = dbus_messaging.GetStatus().to!(Variant!DBusAny[string])();
    try {
        auto text = dbus_messaging.Get("org.freedesktop.ModemManager1.Sms", "Text").to!string();
        loginfo("Sms received: ", text);
        return text;
    }
    catch (DBusException e) {
        logerror("Sms message disappeared before it could be accessed.");
        return null;
    }
}

void main(string[] args) {

    try {
        // dfmt off
        auto helpInformation = getopt(args,
            std.getopt.config.passThrough,
            "log|l", "Logging Level [DEBUG,INFO,WARN,ERROR,NONE*]\t* default", &loggingLevel,
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

    logdebug("Starting");

    logdebug("Opening clipboard");
    clipboard = new XClipboard();

    loginfo("Registering notification signals");
    // setup router for receiving message from notifications
    // receive message
    DBusError err;
    dbus_bus_add_match(sessbus.conn,
        "type='signal',interface='org.freedesktop.Notifications'",
        &err); // see signals from the given interface
    dbus_connection_flush(sessbus.conn);

    auto router = new MessageRouter();
    MessagePattern patt = MessagePattern("/org/freedesktop/Notifications",
        "org.freedesktop.Notifications",
        "ActionInvoked", true);
    router.setHandler!(void, uint, string)(patt, toDelegate(&copyToClipboardClicked));

    MessagePattern patt3 = MessagePattern("/org/freedesktop/Notifications",
        "org.freedesktop.Notifications",
        "NotificationClosed", true);
    router.setHandler!(void, uint, uint)(patt3, toDelegate(&notificationClosed));

    // install router
    registerRouter(sessbus, router);

    loginfo("Registering modem signal");

    // setup modem manager sms notifications

    auto router2 = new MessageRouter();
    dbus_bus_add_match(sysbus.conn,
        "type='signal',interface='org.freedesktop.ModemManager1.Modem.Messaging'",
        &err);
    dbus_connection_flush(sysbus.conn);

    MessagePattern patt2 = MessagePattern("/org/freedesktop/ModemManager1/Modem/0",
        "org.freedesktop.ModemManager1.Modem.Messaging",
        "Added", true);
    router2.setHandler!(void, ObjectPath, bool)(patt2, toDelegate(&smsReceived));

    // install router
    registerRouter(sysbus, router2);

    logdebug("Starting event loop");
    while (true) {
        // TODO: DBus probably also supports blocking i/o
        sysbus.tick();
        sessbus.tick();
        Thread.sleep(500.msecs);
    }
}
