// File created from src/messages.mes on Fri Feb 14 2020 17:32

#include <cstddef>
#include <log/message_types.h>
#include <log/message_initializer.h>

extern const isc::log::MessageID GRAPE_QUERY = "GRAPE_QUERY";
extern const isc::log::MessageID GRAPE_LOAD = "GRAPE_LOAD";
extern const isc::log::MessageID GRAPE_PACKET_OPTIONS_SKIPPED = "GRAPE_PACKET_OPTIONS_SKIPPED";
extern const isc::log::MessageID GRAPE_PACKET_UNPACK_FAILED = "GRAPE_PACKET_UNPACK_FAILED";
extern const isc::log::MessageID GRAPE_UNLOAD = "GRAPE_UNLOAD";

namespace {

const char* values[] = {
    "GRAPE_QUERY", "recognized a GRAPE HOOK query: %1",
    "GRAPE_LOAD", "Grape hooks library has been loaded",
    "GRAPE_PACKET_OPTIONS_SKIPPED", "an error upacking an option, caused subsequent options to be skipped: %1",
    "GRAPE_PACKET_UNPACK_FAILED", "failed to parse query from %1 to %2, received over interface %3, reason: %4",
    "GRAPE_UNLOAD", "Grape hooks library has been unloaded",
    NULL
};

const isc::log::MessageInitializer initializer(values);

} // Anonymous namespace

