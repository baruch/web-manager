AM_CFLAGS = \
	$(ALL_CFLAGS) \
	-include $(CONFIG_HEADER)

VALAFLAGS = \
	--thread \
	--vapidir vapi \
	--pkg dbus-glib-1 \
	--pkg gee-1.0 \
	--pkg gio-2.0 \
	--pkg libsoup-2.4

bin_PROGRAMS = web-manager

web_manager_SOURCES = \
	main.vala

web_manager_LDADD = $(ALL_LIBS)
