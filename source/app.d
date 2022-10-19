import std.stdio;
import std.conv;
import std.functional : toDelegate;

import core.thread;

import ddbus;
import ddbus.c_lib;

import xclipboard;

Connection sessbus;
Connection sysbus;

XClipboard clipboard;

// FIXME: bad bad bad
string smstext;
uint id;

// TODO: move to main. Now it crashes because assignment copies the object
// which involves a construct/destruct cycle. This closes the connection
static this() {
    sysbus = connectToBus(DBusBusType.DBUS_BUS_SYSTEM);
    sessbus = connectToBus();
}

void copyToClipboardClicked(uint id, string action_key) {
    writeln("Id: ",id," Signal: " ~ action_key);
    clipboard.copyTo(smstext);
}

void smsReceived(ObjectPath path, bool val) {
    writeln("Added: path: ", path, " received: ", val ? "yes" : "no");
    if (val) {
        writeln("Message received from radio");
        string text = getSmsMessage(path);
        sendNotification(text);
        smstext = text;
    } else {
        writeln("Message added locally");
    }
}

void sendNotification(string text) {

    // Send message

    PathIface dbus_notify = new PathIface(sessbus, "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications", "org.freedesktop.Notifications");
    string[] list; // must have even num elements. even elem = action, odd elem = message to user
    list ~= "CopyToClipboard";
    list ~= "Copy";
    Variant!DBusAny[string] map;

    Message msg = dbus_notify.Notify("SMS Received", cast(uint) 0, "mail-message-new-list", "A SMS message was received",
        text, list, map, 10000);
    id = msg.to!uint();
    writeln("Created notification id: ",id);
}

string getSmsMessage(ObjectPath path) {

    PathIface dbus_messaging= new PathIface(sysbus, "org.freedesktop.ModemManager1",
     path,"org.freedesktop.DBus.Properties");
    //auto res = dbus_messaging.GetStatus().to!(Variant!DBusAny[string])();
    auto text = dbus_messaging.Get("org.freedesktop.ModemManager1.Sms","Text").to!string();

    writeln("Sms received: ",text);
    return text;
}

void main() {

    clipboard = new XClipboard();

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

    // install router
    registerRouter(sessbus, router);

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


    while (true) {
        // TODO: DBus probably also supports blocking i/o
        sysbus.tick();
        sessbus.tick();
        Thread.sleep(1.seconds);
    }
}

