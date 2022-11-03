import std.stdio;
import std.conv;
import std.functional : toDelegate;
import std.regex;
import std.array;
import std.algorithm;
import std.getopt;

import core.thread;

import ddbus;
import ddbus.c_lib;

import logging;
import xclipboard;

XClipboard clipboard;

Connection sessbus;
Connection sysbus;

enum NotificationClosedReason {
    Expired = 1,
    DismissedByUser = 2,
    ClosedByCode = 3,
    UndefinedReserved = 4
}

struct Notification {
    uint id;
    ObjectPath sms_path;
    string number;
}

// FIXME: bad bad bad
Notification[uint] notifications;

// TODO: move to main. Now it crashes because assignment copies the object
// which involves a construct/destruct cycle. This closes the connection
static this() {
    sysbus = connectToBus(DBusBusType.DBUS_BUS_SYSTEM);
    sessbus = connectToBus();
}

void notificationActionInvoked(uint id, string action_key) {
    logdebug("notificationActionInvoked(): " ~ to!string(id) ~ ", action: " ~ action_key);
    // TODO: check if id is a notification that I sent
    Notification* notification = id in notifications;
    if (notification == null) {
        logdebug("Ignoring action '" ~ action_key ~ "' for non-owned notification.");
        return;
    }

    if (action_key == "copy" || action_key == "copydelete") {
        loginfo("copy to clip: Id: ", id, " value: " ~ notification.number);
        clipboard.copyTo(notification.number);
    }
    if (action_key == "copydelete") {
        deleteSmsMessage(notification.sms_path);
    }
    // have the garbage collector delete it
    clipboard = null;

}

void notificationClosed(uint id, uint reason) {
    if (id !in notifications) {
        logdebug("Notification closed but not mine. Not taking action.");
        return;
    }
    loginfo("Closed notification: ", id, " reasoncode: ", reason.to!NotificationClosedReason);
    notifications.remove(id);
    loginfo("Messages in list: ", notifications.keys);
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
    // find first number in the text.
    string number;
    auto r = regex(r"\d+");
    number = matchFirst(text, r).hit;

    sendNotification(text, path, number);

}

void sendNotification(string text, ObjectPath path, string number) {

    // Send message

    PathIface dbus_notify = new PathIface(sessbus, "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications", "org.freedesktop.Notifications");
    string[] list; // must have even num elements. even elem = action, odd elem = message to user
    list ~= "copy"; //action key for use with notification handler
    list ~= "Copy " ~ number; // user message
    list ~= "copydelete";
    list ~= "Copy " ~ number ~ " and delete";

    Variant!DBusAny[string] map;

    Message msg = dbus_notify.Notify("SMS Received", cast(uint) 0, "mail-message-new-list", "A SMS message was received",
        text, list, map, 10000);

    uint id = msg.to!uint();
    Notification notification = Notification(id, path, number);
    notifications[id] = notification;
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
        logerror(e.message);
        return null;
    }
}

void deleteSmsMessage(ObjectPath path) {
    PathIface dbus_messaging = new PathIface(sysbus, "org.freedesktop.ModemManager1",
        "/org/freedesktop/ModemManager1/Modem/0", "org.freedesktop.ModemManager1.Modem.Messaging");
    try {
        loginfo("Deleting SMS");
        dbus_messaging.Delete(path);
    }
    catch (DBusException e) {
        logerror("Sms message disappeared before it could be deleted.");
    }
}

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

    logdebug("Opening clipboard");
    clipboard = new XClipboard();
    if (clipboard is null) {
        logerror("Can't open clipboard");
        return;
    }

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
    router.setHandler!(void, uint, string)(patt, toDelegate(&notificationActionInvoked));

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
        
        clipboard.processSelectionEvents();
        
        Thread.sleep(500.msecs);

    }
}
