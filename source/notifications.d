module notifications;

void DBusClientNotificationsProc(LogLevel ll) {

    Connection sessbus = connectToBus();
    scope(exit) sessbus.close();

    setDefaultLoggingLevel(ll);
    logdebug("Starting dbus notification thread");

    // setup router for receiving message from notifications
    // receive message
    DBusError err;
    dbus_bus_add_match(sessbus.conn,
        "type='signal',interface='org.freedesktop.Notifications'",
        &err); // allow to receive signals from the given interface
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
    logdebug("DBUS: Waiting for notification messages");
    registerRouter(sessbus, router);

    sessbus.simpleMainLoop();
}
