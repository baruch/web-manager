AM_CFLAGS = \
	$(DBUS_CFLAGS) \
	$(GEE_CFLAGS) \
	$(FSO_GLIB_CFLAGS) \
	$(GIO_CFLAGS) \
	-include $(CONFIG_HEADER)

VALACFLAGS = \
	--vapidir vapi \
	--pkg dbus-glib-1 \
	--pkg gee-1.0 \
	--pkg gio-2.0

bin_PROGRAMS = web-manager

web_manager_SOURCES = \
	main.vala

web_manager_LDADD = \
	$(DBUS_LIBS) \
	$(GEE_LIBS) \
	$(GIO_LIBS) \
	$(SQLITE_LIBS)
