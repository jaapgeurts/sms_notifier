module modem;


void modemAdded(ObjectPath path, ddbus.Variant!DBusAny[string][string]) {
    loginfo("Modem add at: ",path);
    // stop and restart the modemproc
}

void modemRemoved(ObjectPath path,string[] interfaces) {
    loginfo("Modem removed at: ",path);
}


ObjectPath getDbusModemPath()
{
    DBusError error;
    Connection conn = Connection(dbus_bus_get_private(DBusBusType.DBUS_BUS_SYSTEM, &error));
    scope (exit) conn.close();

    PathIface dbus_messaging = new PathIface(conn, "org.freedesktop.ModemManager1",
        "/org/freedesktop/ModemManager1", "org.freedesktop.DBus.ObjectManager");

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

void DBusClientModemProc(LogLevel ll) {
    // TODO: make thread accessible

    Connection sysbus = connectToBus(DBusBusType.DBUS_BUS_SYSTEM);
    scope(exit) sysbus.close();

    setDefaultLoggingLevel(ll);
    logdebug("Starting dbus modem thread");


    DBusError err;

    // setup modem manager sms notifications
    auto router2 = new MessageRouter();
    // TODO: Write decent wrapper: add signal MessageRoute as well
    dbus_bus_add_match(sysbus.conn,
        "type='signal',interface='org.freedesktop.ModemManager1.Modem.Messaging'",
        &err); // allow to receive signals from the given interface
    dbus_bus_add_match(sysbus.conn,
        "type='signal',interface='org.freedesktop.DBus.ObjectManager'",
        &err); // allow to receive signals from the given interface
    dbus_connection_flush(sysbus.conn);

    const ObjectPath lp = dbusModemPath; // make a copy of a shared value
    MessagePattern patt2 = MessagePattern(lp.value(),
        "org.freedesktop.ModemManager1.Modem.Messaging",
        "Added", true);
    router2.setHandler!(void, ObjectPath, bool)(patt2, toDelegate(&smsReceived));

    MessagePattern patt3 = MessagePattern("/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager",
        "InterfacesRemoved", true);
    router2.setHandler!(void, ObjectPath,string[])(patt3, toDelegate(&modemRemoved));

    MessagePattern patt4 = MessagePattern("/org/freedesktop/ModemManager1",
        "org.freedesktop.DBus.ObjectManager",
        "InterfacesAdded", true);
    router2.setHandler!(void, ObjectPath,ddbus.Variant!DBusAny[string][string])(patt4, toDelegate(&modemAdded));

    // install router
    registerRouter(sysbus, router2);

    logdebug("DBUS: waiting for modem messages");
    sysbus.simpleMainLoop();
}
