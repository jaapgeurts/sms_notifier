module modem;

import std.functional : toDelegate;
import std.regex;
import core.thread;

import ddbus;
import ddbus.c_lib;

import notifications;
import logging;

private shared ObjectPath dbusModemPath;
private MessageRouter router2;
private MessagePattern modemHandlerPattern;

void DBusClientModemProc(LogLevel ll) {
    // TODO: make thread accessible

    dbusModemPath = getDbusModemPath();

    Connection sysbus = connectToBus(DBusBusType.DBUS_BUS_SYSTEM);
    scope(exit) sysbus.close();

    setDefaultLoggingLevel(ll);
    logdebug("Starting dbus modem thread");


    DBusError err;

    // setup modem manager sms notifications
    router2 = new MessageRouter();
    // TODO: Write decent wrapper: add signal MessageRoute as well
    dbus_bus_add_match(sysbus.conn,
        "type='signal',interface='org.freedesktop.ModemManager1.Modem.Messaging'",
        &err); // allow to receive signals from the given interface
    dbus_bus_add_match(sysbus.conn,
        "type='signal',interface='org.freedesktop.DBus.ObjectManager'",
        &err); // allow to receive signals from the given interface
    dbus_connection_flush(sysbus.conn);

    MessagePattern patt3 = MessagePattern(ObjectPath("/org/freedesktop/ModemManager1"),
        interfaceName("org.freedesktop.DBus.ObjectManager"),
        "InterfacesRemoved", true);
    router2.setHandler!(void, ObjectPath,string[])(patt3, toDelegate(&onModemRemoved));

    MessagePattern patt4 = MessagePattern(ObjectPath("/org/freedesktop/ModemManager1"),
        interfaceName("org.freedesktop.DBus.ObjectManager"),
        "InterfacesAdded", true);
    router2.setHandler!(void, ObjectPath,ddbus.Variant!DBusAny[string][string])(patt4, toDelegate(&onModemAdded));

    addModemHandlers(dbusModemPath);

    // install router
    registerRouter(sysbus, router2);

    logdebug("DBUS: waiting for modem messages");
    sysbus.simpleMainLoop();
}

private void addModemHandlers(ObjectPath modemPath) {
    modemHandlerPattern = MessagePattern(modemPath,
        interfaceName("org.freedesktop.ModemManager1.Modem.Messaging"),
        "Added", true);
    router2.setHandler!(void, ObjectPath, bool)(modemHandlerPattern, toDelegate(&onSmsReceived));

}

private void removeModemHandlers() {
    router2.removeHandler(modemHandlerPattern);
}

// TODO: consider deleting sms not by path, but by modem ID and sms ID
public void deleteSmsMessage(string objPath) {
    DBusError error;
    Connection conn = Connection(dbus_bus_get_private(DBusBusType.DBUS_BUS_SYSTEM, &error));
    scope (exit) conn.close();

    const ObjectPath lp = dbusModemPath;
    PathIface dbus_messaging = new PathIface(conn,
        busName("org.freedesktop.ModemManager1"),
        lp, interfaceName("org.freedesktop.ModemManager1.Modem.Messaging"));
    try {
        loginfo("Deleting SMS");
        ObjectPath path = objPath;
        dbus_messaging.Delete(path);
    }
    catch (DBusException e) {
        logerror("Sms message disappeared before it could be deleted.");
    }
}

private void onModemAdded(ObjectPath path, ddbus.Variant!DBusAny[string][string]) {
    loginfo("Modem add at: ",path);
    // stop and restart the modemproc
    removeModemHandlers();

    addModemHandlers(path);
}

private void onModemRemoved(ObjectPath path,string[] interfaces) {
    loginfo("Modem removed at: ",path);
    removeModemHandlers();
}

private void onSmsReceived(ObjectPath path, bool val) {
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
    auto matches = matchFirst(text, r);
    sendNotification(text, path.toString(), matches.length >0 ? matches.hit:"");

}

private string getSmsMessage(ObjectPath path) {
    DBusError error;
    Connection conn = Connection(dbus_bus_get_private(DBusBusType.DBUS_BUS_SYSTEM, &error));
    scope (exit) conn.close();

    PathIface dbus_messaging = new PathIface(conn, busName("org.freedesktop.ModemManager1"),
        path, interfaceName("org.freedesktop.DBus.Properties"));
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

private ObjectPath getDbusModemPath()
{
    DBusError error;
    Connection conn = Connection(dbus_bus_get_private(DBusBusType.DBUS_BUS_SYSTEM, &error));
    scope (exit) conn.close();

    PathIface dbus_messaging = new PathIface(conn,
        busName("org.freedesktop.ModemManager1"),
        ObjectPath("/org/freedesktop/ModemManager1"),
        interfaceName("org.freedesktop.DBus.ObjectManager"));

    //out ARRAY of DICT_ENTRY<OBJPATH,ARRAY of DICT_ENTRY<STRING,ARRAY of DICT_ENTRY<STRING,VARIANT>>> objpath_interfaces_and_properties
    //ddbus.Variant!DBusAny[string]
    auto dict = dbus_messaging.GetManagedObjects().to!(ddbus.Variant!DBusAny[ObjectPath]);
    if (dict.length >0) {
        loginfo("Found ",dict.length, " modems. Using the first one found");
        return dict.keys[0];
    }

    logerror("There are no modems in your system");

    return ObjectPath();
}


