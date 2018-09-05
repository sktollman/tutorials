/* -*- P4_16 -*- */
#include <core.p4>
#include <sume_switch.p4>

// NOTE: new type added here
const bit<16> TYPE_MYTUNNEL = 0x1212;
const bit<16> TYPE_IPV4 = 0x800;

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<8>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

// NOTE: added new header type
header myTunnel_t {
    bit<16> proto_id;
    bit<16> dst_id;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}

// NOTE: Added new header type to struct
// List of all recognized headers
struct Parsed_packet {
    ethernet_t ethernet;
    myTunnel_t   myTunnel;
    ipv4_t ipv4;
}

// user defined metadata: can be used to share information between
// TopParser, TopPipe, and TopDeparser
struct user_metadata_t {
    bit<8> unused;
}

// digest data, MUST be 256 bits
struct digest_data_t {
    bit<256>  unused;
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

// TODO: Update the parser to parse the myTunnel header as well
@Xilinx_MaxPacketRegion(1024)
parser TopParser(packet_in b,
                out Parsed_packet p,
                out user_metadata_t user_metadata,
                out digest_data_t digest_data,
                inout sume_metadata_t sume_metadata) {

    state start {
        transition parse_ethernet;
    }

    state parse_ethernet {
        b.extract(p.ethernet);
        transition select(p.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        b.extract(p.ipv4);
        transition accept;
    }

}

/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control TopPipe(inout Parsed_packet p,
                inout user_metadata_t user_metadata,
                inout digest_data_t digest_data,
                inout sume_metadata_t sume_metadata) {
    action drop() {
        sume_metadata.dst_port = 0;
    }

    action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
        sume_metadata.dst_port = port;
        p.ethernet.srcAddr = p.ethernet.dstAddr;
        p.ethernet.dstAddr = dstAddr;
        p.ipv4.ttl = p.ipv4.ttl - 1;
    }

    table ipv4_lpm {
        key = {
            p.ipv4.dstAddr: lpm;
        }
        actions = {
            ipv4_forward;
            drop;
            NoAction;
        }
        size = 1024;
        default_action = drop();
    }

    // TODO: declare a new action: myTunnel_forward(egressSpec_t port)


    // TODO: declare a new table: myTunnel_exact
    // TODO: also remember to add table entries!

    apply {
        // TODO: Update control flow
        if (p.ipv4.isValid()) {
            ipv4_lpm.apply();
        }
    }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

@Xilinx_MaxPacketRegion(1024)
control TopDeparser(packet_out b,
                    in Parsed_packet p,
                    in user_metadata_t user_metadata,
                    inout digest_data_t digest_data,
                    inout sume_metadata_t sume_metadata) {
    apply {
        b.emit(p.ethernet);
        // TODO: emit myTunnel header as well
        b.emit(p.ipv4);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

SimpleSumeSwitch(TopParser(), TopPipe(), TopDeparser()) main;
