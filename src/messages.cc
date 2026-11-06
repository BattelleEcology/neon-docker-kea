// File created from src/messages.mes

#include <cstddef>
#include <log/message_types.h>
#include <log/message_initializer.h>

extern const isc::log::MessageID GRAPE_LOAD = "GRAPE_LOAD";
extern const isc::log::MessageID GRAPE_PACKET_UNPACK_FAILED = "GRAPE_PACKET_UNPACK_FAILED";
extern const isc::log::MessageID GRAPE_QUERY = "GRAPE_QUERY";
extern const isc::log::MessageID GRAPE_UNLOAD = "GRAPE_UNLOAD";

namespace {

const char* values[] = {
    "GRAPE_LOAD", "Grape hooks library has been loaded",
    "GRAPE_PACKET_UNPACK_FAILED", "failed to parse query from %1 to %2, received over interface %3, reason: %4",
    "GRAPE_QUERY", "cleared the N flag of the Client FQDN option in a query from %1",
    "GRAPE_UNLOAD", "Grape hooks library has been unloaded",
    NULL
};

const isc::log::MessageInitializer initializer(values);

} // Anonymous namespace

