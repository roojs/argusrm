#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <netioapi.h>
#include <string.h>
#include <stdint.h>
#include "adapter-row.h"

uint32_t argus_adapter_address(uint64_t luid, const char *ip, uint8_t prefix)
{
	MIB_UNICASTIPADDRESS_ROW row;
	IN_ADDR addr;
	NET_LUID id;

	InitializeUnicastIpAddressEntry(&row);
	if (InetPtonA(AF_INET, ip, &addr) != 1) {
		return ERROR_INVALID_PARAMETER;
	}
	memcpy(&id, &luid, sizeof(id));
	row.InterfaceLuid = id;
	row.Address.Ipv4.sin_family = AF_INET;
	row.Address.Ipv4.sin_addr = addr;
	row.OnLinkPrefixLength = prefix;
	row.DadState = IpDadStatePreferred;
	return CreateUnicastIpAddressEntry(&row);
}

uint32_t argus_adapter_route(uint64_t luid, const char *ip)
{
	MIB_IPFORWARD_ROW2 route;
	NET_LUID id;

	InitializeIpForwardEntry(&route);
	memcpy(&id, &luid, sizeof(id));
	route.InterfaceLuid = id;
	route.DestinationPrefix.Prefix.Ipv4.sin_family = AF_INET;
	if (InetPtonA(AF_INET, ip, &route.DestinationPrefix.Prefix.Ipv4.sin_addr) != 1) {
		return ERROR_INVALID_PARAMETER;
	}
	route.DestinationPrefix.PrefixLength = 32;
	route.NextHop.Ipv4.sin_family = AF_INET;
	route.Metric = 5;
	return CreateIpForwardEntry2(&route);
}

uint32_t argus_adapter_neighbor(uint64_t luid, const char *ip)
{
	MIB_IPNET_ROW2 row;
	NET_LUID id;

	memset(&row, 0, sizeof(row));
	memcpy(&id, &luid, sizeof(id));
	row.InterfaceLuid = id;
	row.Address.Ipv4.sin_family = AF_INET;
	if (InetPtonA(AF_INET, ip, &row.Address.Ipv4.sin_addr) != 1) {
		return ERROR_INVALID_PARAMETER;
	}
	row.PhysicalAddress[0] = 0x02;
	row.PhysicalAddress[5] = 0x01;
	row.PhysicalAddressLength = 6;
	row.State = NlnsReachable;
	return CreateIpNetEntry2(&row);
}

void argus_adapter_read(uint8_t *dest, const void *src, uint32_t n)
{
	memcpy(dest, src, n);
}

void argus_adapter_write(void *dest, const uint8_t *src, uint32_t n)
{
	memcpy(dest, src, n);
}

void argus_adapter_move(uint8_t *dest, uint32_t dest_off, const uint8_t *src, uint32_t n)
{
	memcpy(dest + dest_off, src, n);
}
