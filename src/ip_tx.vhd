-- IP transmitter module
--
-- Author: Antony Gillette
-- Date: 03/2017

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY ip_tx IS
    GENERIC (
        -- Input and output bus width in bytes, must be a power of 2
        width : POSITIVE := 8
    );
    PORT (
        -- All ports are assumed to be synchronous with Clk
        Clk : IN STD_LOGIC;
        Rst : IN STD_LOGIC;
        -- Data input bus for the MAC from the UDP module.
        -- Byte offsets (all integer types are big endian):
        -- 0: Source IP address
        -- 4: Destination IP address
        -- 8: Protocol
        -- 9: UDP datagram
        Data_in : IN STD_LOGIC_VECTOR(width * 8 - 1 DOWNTO 0);
        -- Assertion indicates which Data_in bytes are valid.
        Data_in_valid : IN STD_LOGIC_VECTOR(width - 1 DOWNTO 0);
        -- Asserted when the first data is available on Data_in.
        Data_in_start : IN STD_LOGIC;
        -- Asserted when the last valid data is available on Data_in.
        Data_in_end : IN STD_LOGIC;
        -- Indicate that there has been an error in the current data stream.
        -- Data_in will be ignored until the next Data_in_start assertion.
        Data_in_err : IN STD_LOGIC;

        -- IPv4 output bus to the MAC.
        -- Byte offsets (all integer types are big endian):
        -- 0: IP version and header length (1 byte)
        -- 2: Total packet length (2 bytes)
        -- 9: Protocol (1 byte)
        -- 10: Header checksum (2 bytes)
        -- 12: Source IP address (4 bytes)
        -- 16: Destination IP address (4 bytes)
        -- 20: IP datagram's data section
        Data_out : OUT STD_LOGIC_VECTOR(width * 8 - 1 DOWNTO 0);
        -- Assertion indicates which Data_out bytes are valid.
        Data_out_valid : OUT STD_LOGIC_VECTOR(width - 1 DOWNTO 0);
        -- Asserted when the first data is available on Data_out.
        Data_out_start : OUT STD_LOGIC;
        -- Asserted when the last data is available on Data_out.
        Data_out_end : OUT STD_LOGIC;
        -- Indicate that there has been an error in the current datagram.
        -- Data_out should be ignored until the next Data_out_start assertion.
        Data_out_err : OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE normal OF ip_tx IS
    CONSTANT UDP_PROTO : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"11";
    TYPE DATA_BUS IS ARRAY (width - 1 DOWNTO 0)
        OF STD_LOGIC_VECTOR(7 DOWNTO 0);
    TYPE BUF IS ARRAY (23 DOWNTO 0) OF STD_LOGIC_VECTOR(7 DOWNTO 0);

    -- Keeping pipeline prefix for potential future addition
    SIGNAL p0_data_in : DATA_BUS;
    SIGNAL p0_data_in_valid
        : STD_LOGIC_VECTOR(Data_in_valid'length - 1 DOWNTO 0);
    SIGNAL p0_data_in_start : STD_LOGIC;
    SIGNAL p0_data_in_end : STD_LOGIC;
    SIGNAL p0_data_in_err : STD_LOGIC;

    SIGNAL p0_buf : BUF;

    SIGNAL p0_ip_hdr_len : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL p0_ip_pkt_len : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL p0_ip_id : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL p0_ip_flag_frag : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL p0_ip_ttl_proto : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL p0_ip_hdr_chk : STD_LOGIC_VECTOR(16 DOWNTO 0);
    SIGNAL p0_ip_addr_src_hi : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL p0_ip_addr_src_lo : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL p0_ip_addr_dst_hi : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL p0_ip_addr_dst_lo : STD_LOGIC_VECTOR(15 DOWNTO 0);

    SIGNAL p0_len_read_place : UNSIGNED(15 DOWNTO 0);
    SIGNAL p0_end_counter_place : UNSIGNED(4 DOWNTO 0);
    SIGNAL data_in_sig : DATA_BUS;

BEGIN
    -- Input signal wiring
    gen_in_data: FOR i IN 0 TO width - 1 GENERATE
        data_in_sig(i) <= Data_in((i + 1) * 8 - 1 DOWNTO i * 8);
    END GENERATE;

    PROCESS(Clk)
        VARIABLE p0_len_read : UNSIGNED(p0_len_read_place'length - 1 DOWNTO 0);
        VARIABLE p0_chk_accum: UNSIGNED(p0_ip_hdr_chk'length - 1 DOWNTO 0);
        VARIABLE p0_buf_counter : UNSIGNED(4 DOWNTO 0);
        VARIABLE p0_end_counter : UNSIGNED(4 DOWNTO 0);
    BEGIN
        IF rising_edge(Clk) THEN
            IF Rst = '1' THEN
                p0_data_in <= (OTHERS => x"00");
                p0_data_in_valid <= (OTHERS => '0');
                p0_data_in_start <= '0';
                p0_data_in_end <= '0';
                p0_data_in_err <= '0';
                p0_len_read_place <= (OTHERS => '0');
                p0_end_counter_place <= (OTHERS => '0');

                p0_buf <= (OTHERS => x"00");

                p0_ip_hdr_len <= x"4500";
                p0_ip_pkt_len <= (OTHERS => '0');
                p0_ip_id <= (OTHERS => '0');
                p0_ip_flag_frag <= (OTHERS => '0');
                p0_ip_ttl_proto <= x"4000";
                p0_ip_hdr_chk <= '0' & x"8500";
                p0_ip_addr_src_hi <= (OTHERS => '0');
                p0_ip_addr_src_lo <= (OTHERS => '0');
                p0_ip_addr_dst_hi <= (OTHERS => '0');
                p0_ip_addr_dst_lo <= (OTHERS => '0');
            ELSE
                p0_data_in <= data_in_sig;
                p0_data_in_valid <= (OTHERS => '0');
                p0_data_in_start <= Data_in_start;
                p0_data_in_end <= '0';
                p0_data_in_err <= Data_in_err;

                p0_len_read := p0_len_read_place;
                p0_end_counter := p0_end_counter_place;
                p0_chk_accum := UNSIGNED(p0_ip_hdr_chk);
                IF Data_in_start = '1' THEN
                    p0_len_read := (OTHERS => '0');
                END IF;
                FOR i IN 0 TO width - 1 LOOP
                    IF Data_in_valid(i) = '1' OR Data_in_end = '1' THEN
                        CASE TO_INTEGER(p0_len_read) IS
                            -- Source Address
                            WHEN 0 =>
                                p0_data_in_valid(i) <= '0';
                                p0_ip_addr_src_hi(15 DOWNTO 8) <= data_in_sig(i);
                            WHEN 1 =>
                                p0_data_in_valid(i) <= '0';
                                p0_ip_addr_src_hi(7 DOWNTO 0) <= data_in_sig(i);
                            WHEN 2 =>
                                p0_data_in_valid(i) <= '0';
                                p0_ip_addr_src_lo(15 DOWNTO 8) <= data_in_sig(i);
                            WHEN 3 =>
                                p0_data_in_valid(i) <= '0';
                                p0_ip_addr_src_lo(7 DOWNTO 0) <= data_in_sig(i);
                            -- Destination Address
                            WHEN 4 =>
                                p0_data_in_valid(i) <= '0';
                                p0_ip_addr_dst_hi(15 DOWNTO 8) <= data_in_sig(i);
                            WHEN 5 =>
                                p0_data_in_valid(i) <= '0';
                                p0_ip_addr_dst_hi(7 DOWNTO 0) <= data_in_sig(i);
                            WHEN 6 =>
                                p0_data_in_valid(i) <= '0';
                                p0_ip_addr_dst_lo(15 DOWNTO 8) <= data_in_sig(i);
                            WHEN 7 =>
                                p0_data_in_valid(i) <= '0';
                                p0_ip_addr_dst_lo(7 DOWNTO 0) <= data_in_sig(i);
                            -- Protocol
                            WHEN 8 =>
                                p0_data_in_valid(i) <= '0';
                                IF data_in_sig(i) /= UDP_PROTO THEN
                                    p0_data_in_err <= '1';
                                END IF;
                                p0_ip_ttl_proto(7 DOWNTO 0) <= data_in_sig(i);

                                p0_chk_accum := p0_chk_accum + x"4011";
                                IF p0_chk_accum(16) = '1' THEN
                                    p0_chk_accum(16) := '0';
                                    p0_chk_accum := p0_chk_accum + 1;
                                END IF;
                            -- Start of UDP Header
                            -- Source Port
                            WHEN 9 =>
                                p0_data_in_valid(i) <= '0';
                                p0_buf(0) <= data_in_sig(i);
                            WHEN 10 =>
                                p0_data_in_valid(i) <= '0';
                                p0_buf(1) <= data_in_sig(i);
                            -- Destination Port
                            WHEN 11 =>
                                p0_data_in_valid(i) <= '0';
                                p0_buf(2) <= data_in_sig(i);
                            WHEN 12 =>
                                p0_data_in_valid(i) <= '0';
                                p0_buf(3) <= data_in_sig(i);
                            -- UDP Packet Length, Start outputting IP header
                            WHEN 13 =>
                                p0_data_in_valid(i) <= '1';
                                p0_data_in(i) <= p0_ip_hdr_len(15 DOWNTO 8);
                                p0_buf(4) <= data_in_sig(i);
                                p0_ip_pkt_len(15 DOWNTO 8 ) <= data_in_sig(i);
                            WHEN 14 =>
                                p0_data_in_valid(i) <= '1';
                                p0_data_in(i) <= p0_ip_hdr_len(7 DOWNTO 0);
                                p0_buf(5) <= data_in_sig(i);
                                p0_ip_pkt_len(7 DOWNTO 0) <= data_in_sig(i);
                                p0_ip_pkt_len <= STD_LOGIC_VECTOR(UNSIGNED(
                                    p0_ip_pkt_len) + 20);
                                p0_chk_accum := p0_chk_accum +
                                    UNSIGNED(p0_ip_pkt_len);
                                IF p0_chk_accum(16) = '1' THEN
                                    p0_chk_accum(16) := '0';
                                    p0_chk_accum := p0_chk_accum + 1;
                                END IF;
                            -- UDP Checksum
                            WHEN 15 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(6) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_pkt_len(15 DOWNTO 8);
                            WHEN 16 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(7) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_pkt_len(7 DOWNTO 0);
                            WHEN 17 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(8) <= data_in_sig(i);
                                p0_data_in(i) <= (OTHERS => '0');
                            WHEN 18 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(9) <= data_in_sig(i);
                                p0_data_in(i) <= (OTHERS => '0');
                            WHEN 19 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(10) <= data_in_sig(i);
                                p0_data_in(i) <= (OTHERS => '0');
                            WHEN 20 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(11) <= data_in_sig(i);
                                p0_data_in(i) <= (OTHERS => '0');
                            WHEN 21 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(12) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_ttl_proto(15 DOWNTO 8);
                            WHEN 22 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(13) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_ttl_proto(7 DOWNTO 0);
                            WHEN 23 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(14) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_hdr_chk(15 DOWNTO 8);
                            WHEN 24 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(15) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_hdr_chk(7 DOWNTO 0);
                            WHEN 25 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(16) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_addr_src_hi(15 DOWNTO 8);
                            WHEN 26 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(17) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_addr_src_hi(7 DOWNTO 0);
                            WHEN 27 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(18) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_addr_src_lo(15 DOWNTO 8);
                            WHEN 28 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(19) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_addr_src_lo(7 DOWNTO 0);
                            WHEN 29 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(20) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_addr_dst_hi(15 DOWNTO 8);
                            WHEN 30 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(21) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_addr_dst_hi(7 DOWNTO 0);
                            WHEN 31 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(22) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_addr_dst_lo(15 DOWNTO 8);
                            WHEN 32 =>
                                p0_data_in_valid(i) <= '1';
                                p0_buf(23) <= data_in_sig(i);
                                p0_data_in(i) <= p0_ip_addr_dst_lo(7 DOWNTO 0);
                            WHEN OTHERS =>
                                p0_data_in_valid(i) <= '1';
                                p0_data_in(i) <= p0_buf(TO_INTEGER(
                                    p0_buf_counter));
                                p0_buf(TO_INTEGER(p0_buf_counter))
                                    <= data_in_sig(i);
                                IF p0_buf_counter = "10111" THEN
                                    p0_buf_counter := "00000";
                                ELSE
                                    p0_buf_counter := p0_buf_counter + 1;
                                END IF;
                        END CASE;
                        IF p0_len_read < 8 AND i MOD 2 = 1 THEN
                            p0_chk_accum := p0_chk_accum + (UNSIGNED(
                                data_in_sig(i-1)) & UNSIGNED(data_in_sig(i)));
                            IF p0_chk_accum(16) = '1' THEN
                                p0_chk_accum(16) := '0';
                                p0_chk_accum := p0_chk_accum + 1;
                            END IF;
                        END IF;
                        IF Data_in_end = '1' AND p0_end_counter < 25 THEN
                            p0_end_counter := p0_end_counter + 1;
                        END IF;
                        IF p0_end_counter > 24 THEN
                            p0_data_in_end <= '1';
                        END IF;
                        p0_len_read := p0_len_read + 1;
                    END IF;
                END LOOP;
                p0_len_read_place <= p0_len_read;
                p0_end_counter_place <= p0_end_counter;
                p0_ip_hdr_chk <= STD_LOGIC_VECTOR(p0_chk_accum);
            END IF;
        END IF;
    END PROCESS;

    -- Output signal wiring
    gen_out_data: FOR i IN 0 TO width - 1 GENERATE
        Data_out((i + 1) * 8 - 1 DOWNTO i * 8) <= p0_data_in(i);
    END GENERATE;
    Data_out_valid <= p0_data_in_valid;
    Data_out_start <= p0_data_in_start;
    Data_out_end <= p0_data_in_end;
    Data_out_err <= p0_data_in_err;
END ARCHITECTURE;