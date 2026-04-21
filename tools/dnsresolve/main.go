package main

import (
	"context"
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"math/rand"
	"net"
	"os"
	"sort"
	"strings"
	"time"
)

const (
	dnsTypeA    = 1
	dnsTypeAAAA = 28
	dnsClassIN  = 1
)

func main() {
	var (
		recordType string
		repeat     int
		intervalMs int
		timeoutMs  int
		serversRaw string
	)

	flag.StringVar(&recordType, "type", "A", "DNS record type: A or AAAA")
	flag.IntVar(&repeat, "repeat", 3, "Number of query rounds")
	flag.IntVar(&intervalMs, "interval-ms", 250, "Pause between query rounds in milliseconds")
	flag.IntVar(&timeoutMs, "timeout-ms", 1200, "Per-query timeout in milliseconds")
	flag.StringVar(&serversRaw, "servers", "", "Comma-separated DNS servers, each optionally with :port")
	flag.Parse()

	if flag.NArg() != 1 {
		fmt.Fprintln(os.Stderr, "usage: dnsresolve [--type A|AAAA] [--repeat N] [--interval-ms N] [--timeout-ms N] [--servers ip:53,ip:53] domain")
		os.Exit(2)
	}

	domain := strings.TrimSpace(flag.Arg(0))
	if domain == "" {
		fmt.Fprintln(os.Stderr, "domain is required")
		os.Exit(2)
	}

	qType, err := parseQType(recordType)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}

	servers := parseServers(serversRaw)
	if len(servers) == 0 {
		servers = []string{"1.1.1.1:53", "8.8.8.8:53"}
	}

	if repeat < 1 {
		repeat = 1
	}
	if intervalMs < 0 {
		intervalMs = 0
	}
	if timeoutMs < 200 {
		timeoutMs = 200
	}

	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	found := map[string]struct{}{}

	for i := 0; i < repeat; i++ {
		for _, server := range servers {
			ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMs)*time.Millisecond)
			ips, err := lookupDNS(ctx, rng, server, domain, qType)
			cancel()
			if err != nil {
				continue
			}
			for _, ip := range ips {
				found[ip] = struct{}{}
			}
		}

		if i+1 < repeat && intervalMs > 0 {
			time.Sleep(time.Duration(intervalMs) * time.Millisecond)
		}
	}

	if len(found) == 0 {
		os.Exit(1)
	}

	out := make([]string, 0, len(found))
	for ip := range found {
		out = append(out, ip)
	}
	sort.Strings(out)
	for _, ip := range out {
		fmt.Println(ip)
	}
}

func parseQType(value string) (uint16, error) {
	switch strings.ToUpper(strings.TrimSpace(value)) {
	case "A", "IPV4":
		return dnsTypeA, nil
	case "AAAA", "IPV6":
		return dnsTypeAAAA, nil
	default:
		return 0, fmt.Errorf("unsupported --type %q", value)
	}
}

func parseServers(raw string) []string {
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		server := strings.TrimSpace(part)
		if server == "" {
			continue
		}
		if _, _, err := net.SplitHostPort(server); err != nil {
			server = net.JoinHostPort(server, "53")
		}
		out = append(out, server)
	}
	return out
}

func lookupDNS(ctx context.Context, rng *rand.Rand, server, domain string, qType uint16) ([]string, error) {
	conn, err := dialDNS(ctx, server)
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	_ = conn.SetDeadline(time.Now().Add(time.Until(deadlineFromContext(ctx))))

	queryID := uint16(rng.Intn(65536))
	packet, err := buildQuery(queryID, domain, qType)
	if err != nil {
		return nil, err
	}

	if _, err := conn.Write(packet); err != nil {
		return nil, err
	}

	buf := make([]byte, 1500)
	n, err := conn.Read(buf)
	if err != nil {
		return nil, err
	}

	return parseResponse(buf[:n], queryID, qType)
}

func dialDNS(ctx context.Context, server string) (net.Conn, error) {
	var d net.Dialer
	return d.DialContext(ctx, "udp", server)
}

func deadlineFromContext(ctx context.Context) time.Time {
	if deadline, ok := ctx.Deadline(); ok {
		return deadline
	}
	return time.Now().Add(1500 * time.Millisecond)
}

func buildQuery(id uint16, domain string, qType uint16) ([]byte, error) {
	var msg []byte
	msg = append(msg, 0, 0, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
	binary.BigEndian.PutUint16(msg[0:2], id)

	labels := strings.Split(strings.TrimSuffix(domain, "."), ".")
	for _, label := range labels {
		if label == "" {
			return nil, errors.New("invalid domain")
		}
		if len(label) > 63 {
			return nil, errors.New("label too long")
		}
		msg = append(msg, byte(len(label)))
		msg = append(msg, label...)
	}
	msg = append(msg, 0x00)

	tmp := make([]byte, 4)
	binary.BigEndian.PutUint16(tmp[0:2], qType)
	binary.BigEndian.PutUint16(tmp[2:4], dnsClassIN)
	msg = append(msg, tmp...)
	return msg, nil
}

func parseResponse(msg []byte, expectedID uint16, qType uint16) ([]string, error) {
	if len(msg) < 12 {
		return nil, errors.New("short dns response")
	}

	id := binary.BigEndian.Uint16(msg[0:2])
	if id != expectedID {
		return nil, errors.New("dns response id mismatch")
	}

	flags := binary.BigEndian.Uint16(msg[2:4])
	if flags&0x8000 == 0 {
		return nil, errors.New("not a dns response")
	}
	if rcode := flags & 0x000F; rcode != 0 {
		return nil, fmt.Errorf("dns error rcode=%d", rcode)
	}

	qdCount := int(binary.BigEndian.Uint16(msg[4:6]))
	anCount := int(binary.BigEndian.Uint16(msg[6:8]))
	nsCount := int(binary.BigEndian.Uint16(msg[8:10]))
	arCount := int(binary.BigEndian.Uint16(msg[10:12]))

	offset := 12
	for i := 0; i < qdCount; i++ {
		next, err := skipName(msg, offset)
		if err != nil {
			return nil, err
		}
		offset = next + 4
		if offset > len(msg) {
			return nil, errors.New("truncated question")
		}
	}

	totalRecords := anCount + nsCount + arCount
	var out []string
	for i := 0; i < totalRecords; i++ {
		next, err := skipName(msg, offset)
		if err != nil {
			return nil, err
		}
		offset = next
		if offset+10 > len(msg) {
			return nil, errors.New("truncated record header")
		}

		rType := binary.BigEndian.Uint16(msg[offset : offset+2])
		rClass := binary.BigEndian.Uint16(msg[offset+2 : offset+4])
		rdLength := int(binary.BigEndian.Uint16(msg[offset+8 : offset+10]))
		offset += 10
		if offset+rdLength > len(msg) {
			return nil, errors.New("truncated record data")
		}

		rData := msg[offset : offset+rdLength]
		offset += rdLength

		if i >= anCount {
			continue
		}
		if rClass != dnsClassIN || rType != qType {
			continue
		}

		switch qType {
		case dnsTypeA:
			if len(rData) == 4 {
				out = append(out, net.IP(rData).String())
			}
		case dnsTypeAAAA:
			if len(rData) == 16 {
				ip := net.IP(rData)
				if !ip.IsLoopback() && !ip.IsLinkLocalUnicast() {
					out = append(out, ip.String())
				}
			}
		}
	}

	if len(out) == 0 {
		return nil, errors.New("no matching answers")
	}
	return out, nil
}

func skipName(msg []byte, offset int) (int, error) {
	for {
		if offset >= len(msg) {
			return 0, errors.New("truncated name")
		}
		length := int(msg[offset])
		if length == 0 {
			return offset + 1, nil
		}
		if length&0xC0 == 0xC0 {
			if offset+1 >= len(msg) {
				return 0, errors.New("truncated compression pointer")
			}
			return offset + 2, nil
		}
		offset++
		if offset+length > len(msg) {
			return 0, errors.New("truncated label")
		}
		offset += length
	}
}
