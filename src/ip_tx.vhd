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
    attribute dont_touch : string;

    TYPE DATA_BUS IS ARRAY (width - 1 DOWNTO 0)
        OF STD_LOGIC_VECTOR(7 DOWNTO 0);
    TYPE BUFF IS ARRAY (63 DOWNTO 0) OF STD_LOGIC_VECTOR(7 DOWNTO 0);

    SIGNAL buf : BUFF;
    SIGNAL valid_buf : STD_LOGIC_VECTOR(63 DOWNTO 0);
    SIGNAL buf_out_counter : UNSIGNED(5 DOWNTO 0);
    SIGNAL end_counter : UNSIGNED(5 DOWNTO 0);

    SIGNAL ip_hdr_len : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL ip_pkt_len : UNSIGNED(15 DOWNTO 0);
    SIGNAL ip_id : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL ip_flag_frag : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL ip_ttl_proto : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL ip_hdr_chk : UNSIGNED(16 DOWNTO 0);
    SIGNAL ip_addr_src_hi : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL ip_addr_src_lo : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL ip_addr_dst_hi : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL ip_addr_dst_lo : STD_LOGIC_VECTOR(15 DOWNTO 0);

    SIGNAL ip_pkt_len_valid : STD_LOGIC;

    SIGNAL p0_end_counter_place : UNSIGNED(4 DOWNTO 0);

    -- attribute dont_touch of p0_len_read_sig : signal is "true";
    SIGNAL p0_data_in : DATA_BUS;
    SIGNAL p0_data_in_valid : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL p0_data_in_start : STD_LOGIC;
    SIGNAL p0_data_in_end : STD_LOGIC;
    SIGNAL p0_data_in_err : STD_LOGIC;
    SIGNAL p0_len_read_sig : UNSIGNED(15 DOWNTO 0);
    SIGNAL p0_chk_accum_sig : UNSIGNED(20 DOWNTO 0);
    attribute dont_touch of p0_chk_accum_sig: signal is "true";
    SIGNAL p0_buf_counter : UNSIGNED(6 DOWNTO 0);

    SIGNAL p1_data_in : DATA_BUS;
    SIGNAL p1_data_in_valid : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL p1_data_in_end : STD_LOGIC;
    SIGNAL p1_data_in_err : STD_LOGIC;
    SIGNAL p1_len_read_sig : UNSIGNED(15 DOWNTO 0);
    SIGNAL p1_chk_accum_sig : UNSIGNED(20 DOWNTO 0);
    attribute dont_touch of p1_chk_accum_sig: signal is "true";
    SIGNAL p1_buf_counter : UNSIGNED(6 DOWNTO 0);

    SIGNAL p2_data_in : DATA_BUS;
    SIGNAL p2_data_in_valid : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL p2_data_in_end : STD_LOGIC;
    SIGNAL p2_data_in_err : STD_LOGIC;
    SIGNAL p2_len_read_sig : UNSIGNED(15 DOWNTO 0);
    SIGNAL p2_chk_accum_sig : UNSIGNED(20 DOWNTO 0);
    attribute dont_touch of p2_chk_accum_sig: signal is "true";
    SIGNAL p2_buf_counter : UNSIGNED(6 DOWNTO 0);

    SIGNAL p3_data_in : DATA_BUS;
    SIGNAL p3_data_in_valid : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL p3_data_in_end : STD_LOGIC;
    SIGNAL p3_data_in_err : STD_LOGIC;
    SIGNAL p3_len_read_sig : UNSIGNED(15 DOWNTO 0);
    SIGNAL p3_chk_accum_sig : UNSIGNED(20 DOWNTO 0);
    attribute dont_touch of p3_chk_accum_sig: signal is "true";
    SIGNAL p3_buf_counter : UNSIGNED(6 DOWNTO 0);

    SIGNAL p4_data_in : DATA_BUS;
    SIGNAL p4_data_in_valid : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL p4_data_in_end : STD_LOGIC;
    SIGNAL p4_data_in_err : STD_LOGIC;
    SIGNAL p4_len_read_sig : UNSIGNED(15 DOWNTO 0);
    SIGNAL p4_chk_accum_sig : UNSIGNED(20 DOWNTO 0);
    attribute dont_touch of p4_chk_accum_sig: signal is "true";
    SIGNAL p4_buf_counter : UNSIGNED(6 DOWNTO 0);

    SIGNAL p5_data_in : DATA_BUS;
    SIGNAL p5_data_in_valid : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL p5_data_in_end : STD_LOGIC;
    SIGNAL p5_data_in_err : STD_LOGIC;
    SIGNAL p5_len_read_sig : UNSIGNED(15 DOWNTO 0);
    SIGNAL p5_chk_accum_sig : UNSIGNED(20 DOWNTO 0);
    attribute dont_touch of p5_chk_accum_sig: signal is "true";
    SIGNAL p5_buf_counter : UNSIGNED(6 DOWNTO 0);

    SIGNAL p6_data_in : DATA_BUS;
    SIGNAL p6_data_in_valid : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL p6_data_in_end : STD_LOGIC;
    SIGNAL p6_data_in_err : STD_LOGIC;
    SIGNAL p6_len_read_sig : UNSIGNED(15 DOWNTO 0);
    SIGNAL p6_chk_accum_sig : UNSIGNED(20 DOWNTO 0);
    attribute dont_touch of p6_chk_accum_sig: signal is "true";
    SIGNAL p6_buf_counter : UNSIGNED(6 DOWNTO 0);

    SIGNAL p7_data_in : DATA_BUS;
    SIGNAL p7_data_in_valid : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL p7_data_in_end : STD_LOGIC;
    SIGNAL p7_data_in_err : STD_LOGIC;
    SIGNAL p7_len_read_sig : UNSIGNED(15 DOWNTO 0);
    attribute dont_touch of p7_len_read_sig: signal is "true";
    SIGNAL p7_chk_accum_sig : UNSIGNED(20 DOWNTO 0);
    attribute dont_touch of p7_chk_accum_sig: signal is "true";
    SIGNAL p7_buf_counter : UNSIGNED(6 DOWNTO 0);

    SIGNAL p8_data_in : DATA_BUS;
    SIGNAL p8_data_in_valid : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL p8_data_in_start : STD_LOGIC;
    SIGNAL p8_data_in_end : STD_LOGIC;
    SIGNAL p8_data_in_err : STD_LOGIC;
    SIGNAL p8_enable : STD_LOGIC;
    SIGNAL p8_output_counter : UNSIGNED(2 DOWNTO 0);
    SIGNAL p8_chk_accum_sig : UNSIGNED(20 DOWNTO 0);

BEGIN
    -- Input signal wiring
    gen_in_data: FOR i IN 0 TO width - 1 GENERATE
        p0_data_in(i) <= Data_in((i + 1) * 8 - 1 DOWNTO i * 8);
    END GENERATE;
    p0_data_in_valid <= Data_in_valid;
    p0_data_in_start <= Data_in_start;
    p0_data_in_end <= Data_in_end;
    p0_data_in_err <= Data_in_err;

    PROCESS(Clk)
        --Here's where variables would go but there aren't any
    BEGIN
        IF rising_edge(Clk) THEN
            IF Rst = '1' THEN
                buf <= (OTHERS => x"00");
                valid_buf <= (OTHERS => '0');
                buf_out_counter <= (OTHERS => '0');
                end_counter <= (OTHERS => '0');

                ip_hdr_len <= x"4500";
                ip_pkt_len <= (OTHERS => '0');
                ip_id <= (OTHERS => '0');
                ip_flag_frag <= (OTHERS => '0');
                ip_ttl_proto <= x"4011";
                ip_hdr_chk <= (OTHERS => '0');
                ip_addr_src_hi <= (OTHERS => '0');
                ip_addr_src_lo <= (OTHERS => '0');
                ip_addr_dst_hi <= (OTHERS => '0');
                ip_addr_dst_lo <= (OTHERS => '0');

                ip_pkt_len_valid <= '0';

                p0_end_counter_place <= (OTHERS => '0');

                p0_len_read_sig <= (OTHERS => '0');
                p0_chk_accum_sig <= (OTHERS => '0');
                p0_buf_counter <= (OTHERS => '0');

                p1_data_in <= (OTHERS => x"00");
                p1_data_in_valid <= (OTHERS => '0');
                p1_data_in_end <= '0';
                p1_data_in_err <= '0';
                p1_len_read_sig <= (OTHERS => '0');
                p1_chk_accum_sig <= (OTHERS => '0');
                p1_buf_counter <= (OTHERS => '0');

                p2_data_in <= (OTHERS => x"00");
                p2_data_in_valid <= (OTHERS => '0');
                p2_data_in_end <= '0';
                p2_data_in_err <= '0';
                p2_len_read_sig <= (OTHERS => '0');
                p2_chk_accum_sig <= (OTHERS => '0');
                p2_buf_counter <= (OTHERS => '0');

                p3_data_in <= (OTHERS => x"00");
                p3_data_in_valid <= (OTHERS => '0');
                p3_data_in_end <= '0';
                p3_data_in_err <= '0';
                p3_len_read_sig <= (OTHERS => '0');
                p3_chk_accum_sig <= (OTHERS => '0');
                p3_buf_counter <= (OTHERS => '0');

                p4_data_in <= (OTHERS => x"00");
                p4_data_in_valid <= (OTHERS => '0');
                p4_data_in_end <= '0';
                p4_data_in_err <= '0';
                p4_len_read_sig <= (OTHERS => '0');
                p4_chk_accum_sig <= (OTHERS => '0');
                p4_buf_counter <= (OTHERS => '0');

                p5_data_in <= (OTHERS => x"00");
                p5_data_in_valid <= (OTHERS => '0');
                p5_data_in_end <= '0';
                p5_data_in_err <= '0';
                p5_len_read_sig <= (OTHERS => '0');
                p5_chk_accum_sig <= (OTHERS => '0');
                p5_buf_counter <= (OTHERS => '0');

                p6_data_in <= (OTHERS => x"00");
                p6_data_in_valid <= (OTHERS => '0');
                p6_data_in_end <= '0';
                p6_data_in_err <= '0';
                p6_len_read_sig <= (OTHERS => '0');
                p6_chk_accum_sig <= (OTHERS => '0');
                p6_buf_counter <= (OTHERS => '0');

                p7_data_in <= (OTHERS => x"00");
                p7_data_in_valid <= (OTHERS => '0');
                p7_data_in_end <= '0';
                p7_data_in_err <= '0';
                p7_len_read_sig <= (OTHERS => '0');
                p7_chk_accum_sig <= (OTHERS => '0');
                p7_buf_counter <= (OTHERS => '0');

                p8_data_in <= (OTHERS => x"00");
                p8_data_in_valid <= (OTHERS => '0');
                p8_data_in_start <= '0';
                p8_data_in_end <= '0';
                p8_data_in_err <= '0';
                p8_enable <= '0';
                p8_output_counter <= (OTHERS => '0');
                p8_chk_accum_sig <= (OTHERS => '0');
            ELSE
                -- For next iteration of Stage 0
                p0_len_read_sig <= p0_len_read_sig + UNSIGNED'(""&p0_data_in_valid(7))
                    + UNSIGNED'(""&p0_data_in_valid(6)) + UNSIGNED'(""&p0_data_in_valid(5))
                    + UNSIGNED'(""&p0_data_in_valid(4)) + UNSIGNED'(""&p0_data_in_valid(3))
                    + UNSIGNED'(""&p0_data_in_valid(2)) + UNSIGNED'(""&p0_data_in_valid(1))
                    + UNSIGNED'(""&p0_data_in_valid(0));
                p1_len_read_sig <= p0_len_read_sig + UNSIGNED'(""&p0_data_in_valid(0));
                p2_len_read_sig <= p1_len_read_sig + UNSIGNED'(""&p1_data_in_valid(1));
                p3_len_read_sig <= p2_len_read_sig + UNSIGNED'(""&p2_data_in_valid(2));
                p4_len_read_sig <= p3_len_read_sig + UNSIGNED'(""&p3_data_in_valid(3));
                p5_len_read_sig <= p4_len_read_sig + UNSIGNED'(""&p4_data_in_valid(4));
                p6_len_read_sig <= p5_len_read_sig + UNSIGNED'(""&p5_data_in_valid(5));
                p7_len_read_sig <= p6_len_read_sig + UNSIGNED'(""&p6_data_in_valid(6));

                -- For reset on receiving end
                IF p0_data_in_end = '1' THEN
                    p0_len_read_sig <= (OTHERS => '0');
                    p0_chk_accum_sig <= (OTHERS => '0');
                END IF;

                -- Start Stage 0 of Pipeline
                IF p0_data_in_valid(0) = '1' THEN
                    p1_chk_accum_sig <= (OTHERS => '0');
                    -- Nothing has been added to p0_len_read_sig yet first time
                    CASE TO_INTEGER(p0_len_read_sig) IS
                    -- Source Address
                        WHEN 0 =>
                            ip_addr_src_hi(15 DOWNTO 8) <= p0_data_in(0);
                        WHEN 1 =>
                            ip_addr_src_hi(7 DOWNTO 0) <= p0_data_in(0);
                            -- Probably need to convert ip_addr_src_hi, etc. to UNSIGNED
                        WHEN 2 =>
                            p1_chk_accum_sig <= "00000"&UNSIGNED(ip_addr_src_hi);
                            ip_addr_src_lo(15 DOWNTO 8) <= p0_data_in(0);
                        WHEN 3 =>
                            ip_addr_src_lo(7 DOWNTO 0) <= p0_data_in(0);
                        -- Destination Address
                        WHEN 4 =>
                            p1_chk_accum_sig <= "00000"&UNSIGNED(ip_addr_src_lo);
                            ip_addr_dst_hi(15 DOWNTO 8) <= p0_data_in(0);
                        WHEN 5 =>
                            ip_addr_dst_hi(7 DOWNTO 0) <= p0_data_in(0);
                        WHEN 6 =>
                            p1_chk_accum_sig <= "00000"&UNSIGNED(ip_addr_dst_hi);
                            ip_addr_dst_lo(15 DOWNTO 8) <= p0_data_in(0);
                        WHEN 7 =>
                            ip_addr_dst_lo(7 DOWNTO 0) <= p0_data_in(0);
                        -- Protocol
                        WHEN 8 =>
                            p1_chk_accum_sig <= "00000"&UNSIGNED(ip_addr_dst_lo);
                            IF p0_data_in(0) /= UDP_PROTO THEN
                                p0_data_in_err <= '1'; --Insert new error here
                            END IF;
                        WHEN 13 =>
                            ip_pkt_len(15 DOWNTO 8) <= UNSIGNED(p0_data_in(0));
                            buf(TO_INTEGER(p0_buf_counter)) <= p0_data_in(0);
                            valid_buf(TO_INTEGER(p0_buf_counter)) <= '1';
                            p0_buf_counter <= (p0_buf_counter + UNSIGNED'(""&p0_data_in_valid(7))
                                + UNSIGNED'(""&p0_data_in_valid(6)) + UNSIGNED'(""&p0_data_in_valid(5))
                                + UNSIGNED'(""&p0_data_in_valid(4)) + UNSIGNED'(""&p0_data_in_valid(3))
                                + UNSIGNED'(""&p0_data_in_valid(2)) + UNSIGNED'(""&p0_data_in_valid(1))
                                + UNSIGNED'(""&p0_data_in_valid(0))) mod 64;
                            p1_buf_counter <= (p0_buf_counter + 1) mod 64;
                        WHEN 14 =>
                            ip_pkt_len <= UNSIGNED(ip_pkt_len) +
                                UNSIGNED(p0_data_in(0)) + 20;
                            buf(TO_INTEGER(p0_buf_counter)) <= p0_data_in(0);
                            valid_buf(TO_INTEGER(p0_buf_counter)) <= '1';
                            p1_chk_accum_sig <= "00000"&UNSIGNED(ip_pkt_len) +
                                UNSIGNED(p0_data_in(0)) + 20;
                            ip_pkt_len_valid <= '1';
                            p0_buf_counter <= (p0_buf_counter + UNSIGNED'(""&p0_data_in_valid(7))
                                + UNSIGNED'(""&p0_data_in_valid(6)) + UNSIGNED'(""&p0_data_in_valid(5))
                                + UNSIGNED'(""&p0_data_in_valid(4)) + UNSIGNED'(""&p0_data_in_valid(3))
                                + UNSIGNED'(""&p0_data_in_valid(2)) + UNSIGNED'(""&p0_data_in_valid(1))
                                + UNSIGNED'(""&p0_data_in_valid(0))) mod 64;
                            p1_buf_counter <= (p0_buf_counter + 1) mod 64;
                        WHEN OTHERS =>
                            buf(TO_INTEGER(p0_buf_counter)) <= p0_data_in(0);
                            valid_buf(TO_INTEGER(p0_buf_counter)) <= '1';
                            p0_buf_counter <= (p0_buf_counter + UNSIGNED'(""&p0_data_in_valid(7))
                                + UNSIGNED'(""&p0_data_in_valid(6)) + UNSIGNED'(""&p0_data_in_valid(5))
                                + UNSIGNED'(""&p0_data_in_valid(4)) + UNSIGNED'(""&p0_data_in_valid(3))
                                + UNSIGNED'(""&p0_data_in_valid(2)) + UNSIGNED'(""&p0_data_in_valid(1))
                                + UNSIGNED'(""&p0_data_in_valid(0))) mod 64;
                            p1_buf_counter <= (p0_buf_counter + 1) mod 64;
                    END CASE;
                END IF;

                -- Start Stage 1 of Pipeline
                IF p1_data_in_valid(1) = '1' THEN
                    p2_chk_accum_sig <= p1_chk_accum_sig;
                    CASE TO_INTEGER(p1_len_read_sig) IS
                    -- Source Address
                        WHEN 0 =>
                            ip_addr_src_hi(15 DOWNTO 8) <= p1_data_in(1);
                        WHEN 1 =>
                            ip_addr_src_hi(7 DOWNTO 0) <= p1_data_in(1);
                            -- Probably need to convert ip_addr_src_hi, etc. to UNSIGNED
                        WHEN 2 =>
                            p2_chk_accum_sig <= p1_chk_accum_sig + UNSIGNED(ip_addr_src_hi);
                            ip_addr_src_lo(15 DOWNTO 8) <= p1_data_in(1);
                        WHEN 3 =>
                            ip_addr_src_lo(7 DOWNTO 0) <= p1_data_in(1);
                        -- Destination Address
                        WHEN 4 =>
                            p2_chk_accum_sig <= p1_chk_accum_sig + UNSIGNED(ip_addr_src_lo);
                            ip_addr_dst_hi(15 DOWNTO 8) <= p1_data_in(1);
                        WHEN 5 =>
                            ip_addr_dst_hi(7 DOWNTO 0) <= p1_data_in(1);
                        WHEN 6 =>
                            p2_chk_accum_sig <= p1_chk_accum_sig + UNSIGNED(ip_addr_dst_hi);
                            ip_addr_dst_lo(15 DOWNTO 8) <= p1_data_in(1);
                        WHEN 7 =>
                            ip_addr_dst_lo(7 DOWNTO 0) <= p1_data_in(1);
                        -- Protocol
                        WHEN 8 =>
                            p2_chk_accum_sig <= p1_chk_accum_sig + UNSIGNED(ip_addr_dst_lo);
                            IF p1_data_in(1) /= UDP_PROTO THEN
                                p1_data_in_err <= '1'; --Insert new error here
                            END IF;
                        WHEN 13 =>
                            ip_pkt_len(15 DOWNTO 8) <= UNSIGNED(p1_data_in(1));
                            buf(TO_INTEGER(p1_buf_counter)) <= p1_data_in(1);
                            valid_buf(TO_INTEGER(p1_buf_counter)) <= '1';
                            p2_buf_counter <= (p1_buf_counter + 1) mod 64;
                        WHEN 14 =>
                            ip_pkt_len <= UNSIGNED(ip_pkt_len) +
                                UNSIGNED(p1_data_in(1)) + 20;
                            buf(TO_INTEGER(p1_buf_counter)) <= p1_data_in(1);
                            valid_buf(TO_INTEGER(p1_buf_counter)) <= '1';
                            p2_chk_accum_sig <= p1_chk_accum_sig + UNSIGNED(
                                ip_pkt_len) + UNSIGNED(p1_data_in(1)) + 20;
                            ip_pkt_len_valid <= '1';
                            p2_buf_counter <= (p1_buf_counter + 1) mod 64;
                        WHEN OTHERS =>
                            buf(TO_INTEGER(p1_buf_counter)) <= p1_data_in(1);
                            valid_buf(TO_INTEGER(p1_buf_counter)) <= '1';
                            p2_buf_counter <= (p1_buf_counter + 1) mod 64;
                    END CASE;
                END IF;

                -- Start Stage 2 of Pipeline
                IF p2_data_in_valid(2) = '1' THEN
                    p3_chk_accum_sig <= p2_chk_accum_sig;
                    CASE TO_INTEGER(p2_len_read_sig) IS
                    -- Source Address
                        WHEN 0 =>
                            ip_addr_src_hi(15 DOWNTO 8) <= p2_data_in(2);
                        WHEN 1 =>
                            ip_addr_src_hi(7 DOWNTO 0) <= p2_data_in(2);
                            -- Probably need to convert ip_addr_src_hi, etc. to UNSIGNED
                        WHEN 2 =>
                            p3_chk_accum_sig <= p2_chk_accum_sig + UNSIGNED(ip_addr_src_hi);
                            ip_addr_src_lo(15 DOWNTO 8) <= p2_data_in(2);
                        WHEN 3 =>
                            ip_addr_src_lo(7 DOWNTO 0) <= p2_data_in(2);
                        -- Destination Address
                        WHEN 4 =>
                            p3_chk_accum_sig <= p2_chk_accum_sig + UNSIGNED(ip_addr_src_lo);
                            ip_addr_dst_hi(15 DOWNTO 8) <= p2_data_in(2);
                        WHEN 5 =>
                            ip_addr_dst_hi(7 DOWNTO 0) <= p2_data_in(2);
                        WHEN 6 =>
                            p3_chk_accum_sig <= p2_chk_accum_sig + UNSIGNED(ip_addr_dst_hi);
                            ip_addr_dst_lo(15 DOWNTO 8) <= p2_data_in(2);
                        WHEN 7 =>
                            ip_addr_dst_lo(7 DOWNTO 0) <= p2_data_in(2);
                        -- Protocol
                        WHEN 8 =>
                            p3_chk_accum_sig <= p2_chk_accum_sig + UNSIGNED(ip_addr_dst_lo);
                            IF p2_data_in(2) /= UDP_PROTO THEN
                                p2_data_in_err <= '1'; --Insert new error here
                            END IF;
                        WHEN 13 =>
                            ip_pkt_len(15 DOWNTO 8) <= UNSIGNED(p2_data_in(2));
                            buf(TO_INTEGER(p2_buf_counter)) <= p2_data_in(2);
                            valid_buf(TO_INTEGER(p2_buf_counter)) <= '1';
                            p3_buf_counter <= (p2_buf_counter + 1) mod 64;
                        WHEN 14 =>
                            ip_pkt_len <= UNSIGNED(ip_pkt_len) +
                                UNSIGNED(p2_data_in(2)) + 20;
                            buf(TO_INTEGER(p2_buf_counter)) <= p2_data_in(2);
                            valid_buf(TO_INTEGER(p2_buf_counter)) <= '1';
                            p3_chk_accum_sig <= p2_chk_accum_sig + UNSIGNED(
                                ip_pkt_len) + UNSIGNED(p2_data_in(2)) + 20;
                            ip_pkt_len_valid <= '1';
                            p3_buf_counter <= (p2_buf_counter + 1) mod 64;
                        WHEN OTHERS =>
                            buf(TO_INTEGER(p2_buf_counter)) <= p2_data_in(2);
                            valid_buf(TO_INTEGER(p2_buf_counter)) <= '1';
                            p3_buf_counter <= (p2_buf_counter + 1) mod 64;
                    END CASE;
                END IF;

                -- Start Stage 3 of Pipeline
                IF p3_data_in_valid(3) = '1' THEN
                    p4_chk_accum_sig <= p3_chk_accum_sig;
                    CASE TO_INTEGER(p3_len_read_sig) IS
                    -- Source Address
                        WHEN 0 =>
                            ip_addr_src_hi(15 DOWNTO 8) <= p3_data_in(3);
                        WHEN 1 =>
                            ip_addr_src_hi(7 DOWNTO 0) <= p3_data_in(3);
                            -- Probably need to convert ip_addr_src_hi, etc. to UNSIGNED
                        WHEN 2 =>
                            p4_chk_accum_sig <= p3_chk_accum_sig + UNSIGNED(ip_addr_src_hi);
                            ip_addr_src_lo(15 DOWNTO 8) <= p3_data_in(3);
                        WHEN 3 =>
                            ip_addr_src_lo(7 DOWNTO 0) <= p3_data_in(3);
                        -- Destination Address
                        WHEN 4 =>
                            p4_chk_accum_sig <= p3_chk_accum_sig + UNSIGNED(ip_addr_src_lo);
                            ip_addr_dst_hi(15 DOWNTO 8) <= p3_data_in(3);
                        WHEN 5 =>
                            ip_addr_dst_hi(7 DOWNTO 0) <= p3_data_in(3);
                        WHEN 6 =>
                            p4_chk_accum_sig <= p3_chk_accum_sig + UNSIGNED(ip_addr_dst_hi);
                            ip_addr_dst_lo(15 DOWNTO 8) <= p3_data_in(3);
                        WHEN 7 =>
                            ip_addr_dst_lo(7 DOWNTO 0) <= p3_data_in(3);
                        -- Protocol
                        WHEN 8 =>
                            p4_chk_accum_sig <= p3_chk_accum_sig + UNSIGNED(ip_addr_dst_lo);
                            IF p3_data_in(3) /= UDP_PROTO THEN
                                p3_data_in_err <= '1'; --Insert new error here
                            END IF;
                        WHEN 13 =>
                            ip_pkt_len(15 DOWNTO 8) <= UNSIGNED(p3_data_in(3));
                            buf(TO_INTEGER(p3_buf_counter)) <= p3_data_in(3);
                            valid_buf(TO_INTEGER(p3_buf_counter)) <= '1';
                            p4_buf_counter <= (p3_buf_counter + 1) mod 64;
                        WHEN 14 =>
                            ip_pkt_len <= UNSIGNED(ip_pkt_len) +
                                UNSIGNED(p3_data_in(3)) + 20;
                            buf(TO_INTEGER(p3_buf_counter)) <= p3_data_in(3);
                            valid_buf(TO_INTEGER(p3_buf_counter)) <= '1';
                            p4_chk_accum_sig <= p3_chk_accum_sig + UNSIGNED(
                                ip_pkt_len) + UNSIGNED(p3_data_in(3)) + 20;
                            ip_pkt_len_valid <= '1';
                            p4_buf_counter <= (p3_buf_counter + 1) mod 64;
                        WHEN OTHERS =>
                            buf(TO_INTEGER(p3_buf_counter)) <= p3_data_in(3);
                            valid_buf(TO_INTEGER(p3_buf_counter)) <= '1';
                            p4_buf_counter <= (p3_buf_counter + 1) mod 64;
                    END CASE;
                END IF;

                -- Start Stage 4 of Pipeline
                IF p4_data_in_valid(4) = '1' THEN
                    p5_chk_accum_sig <= p4_chk_accum_sig;
                    CASE TO_INTEGER(p4_len_read_sig) IS
                    -- Source Address
                        WHEN 0 =>
                            ip_addr_src_hi(15 DOWNTO 8) <= p4_data_in(4);
                        WHEN 1 =>
                            ip_addr_src_hi(7 DOWNTO 0) <= p4_data_in(4);
                            -- Probably need to convert ip_addr_src_hi, etc. to UNSIGNED
                        WHEN 2 =>
                            p5_chk_accum_sig <= p4_chk_accum_sig + UNSIGNED(ip_addr_src_hi);
                            ip_addr_src_lo(15 DOWNTO 8) <= p4_data_in(4);
                        WHEN 3 =>
                            ip_addr_src_lo(7 DOWNTO 0) <= p4_data_in(4);
                        -- Destination Address
                        WHEN 4 =>
                            p5_chk_accum_sig <= p4_chk_accum_sig + UNSIGNED(ip_addr_src_lo);
                            ip_addr_dst_hi(15 DOWNTO 8) <= p4_data_in(4);
                        WHEN 5 =>
                            ip_addr_dst_hi(7 DOWNTO 0) <= p4_data_in(4);
                        WHEN 6 =>
                            p5_chk_accum_sig <= p4_chk_accum_sig + UNSIGNED(ip_addr_dst_hi);
                            ip_addr_dst_lo(15 DOWNTO 8) <= p4_data_in(4);
                        WHEN 7 =>
                            ip_addr_dst_lo(7 DOWNTO 0) <= p4_data_in(4);
                        -- Protocol
                        WHEN 8 =>
                            p5_chk_accum_sig <= p4_chk_accum_sig + UNSIGNED(ip_addr_dst_lo);
                            IF p4_data_in(4) /= UDP_PROTO THEN
                                p4_data_in_err <= '1'; --Insert new error here
                            END IF;
                        WHEN 13 =>
                            ip_pkt_len(15 DOWNTO 8) <= UNSIGNED(p4_data_in(4));
                            buf(TO_INTEGER(p4_buf_counter)) <= p4_data_in(4);
                            valid_buf(TO_INTEGER(p4_buf_counter)) <= '1';
                            p5_buf_counter <= (p4_buf_counter + 1) mod 64;
                        WHEN 14 =>
                            ip_pkt_len <= UNSIGNED(ip_pkt_len) +
                                UNSIGNED(p4_data_in(4)) + 20;
                            buf(TO_INTEGER(p4_buf_counter)) <= p4_data_in(4);
                            valid_buf(TO_INTEGER(p4_buf_counter)) <= '1';
                            p5_chk_accum_sig <= p4_chk_accum_sig + UNSIGNED(
                                ip_pkt_len) + UNSIGNED(p4_data_in(4)) + 20;
                            ip_pkt_len_valid <= '1';
                            p5_buf_counter <= (p4_buf_counter + 1) mod 64;
                        WHEN OTHERS =>
                            buf(TO_INTEGER(p4_buf_counter)) <= p4_data_in(4);
                            valid_buf(TO_INTEGER(p4_buf_counter)) <= '1';
                            p5_buf_counter <= (p4_buf_counter + 1) mod 64;
                    END CASE;
                END IF;

                -- Start Stage 5 of Pipeline
                IF p5_data_in_valid(5) = '1' THEN
                    p6_chk_accum_sig <= p5_chk_accum_sig;
                    CASE TO_INTEGER(p5_len_read_sig) IS
                    -- Source Address
                        WHEN 0 =>
                            ip_addr_src_hi(15 DOWNTO 8) <= p5_data_in(5);
                        WHEN 1 =>
                            ip_addr_src_hi(7 DOWNTO 0) <= p5_data_in(5);
                            -- Probably need to convert ip_addr_src_hi, etc. to UNSIGNED
                        WHEN 2 =>
                            p6_chk_accum_sig <= p5_chk_accum_sig + UNSIGNED(ip_addr_src_hi);
                            ip_addr_src_lo(15 DOWNTO 8) <= p5_data_in(5);
                        WHEN 3 =>
                            ip_addr_src_lo(7 DOWNTO 0) <= p5_data_in(5);
                        -- Destination Address
                        WHEN 4 =>
                            p6_chk_accum_sig <= p5_chk_accum_sig + UNSIGNED(ip_addr_src_lo);
                            ip_addr_dst_hi(15 DOWNTO 8) <= p5_data_in(5);
                        WHEN 5 =>
                            ip_addr_dst_hi(7 DOWNTO 0) <= p5_data_in(5);
                        WHEN 6 =>
                            p6_chk_accum_sig <= p5_chk_accum_sig + UNSIGNED(ip_addr_dst_hi);
                            ip_addr_dst_lo(15 DOWNTO 8) <= p5_data_in(5);
                        WHEN 7 =>
                            ip_addr_dst_lo(7 DOWNTO 0) <= p5_data_in(5);
                        -- Protocol
                        WHEN 8 =>
                            p6_chk_accum_sig <= p5_chk_accum_sig + UNSIGNED(ip_addr_dst_lo);
                            IF p5_data_in(5) /= UDP_PROTO THEN
                                p5_data_in_err <= '1'; --Insert new error here
                            END IF;
                        WHEN 13 =>
                            ip_pkt_len(15 DOWNTO 8) <= UNSIGNED(p5_data_in(5));
                            buf(TO_INTEGER(p5_buf_counter)) <= p5_data_in(5);
                            valid_buf(TO_INTEGER(p5_buf_counter)) <= '1';
                            p6_buf_counter <= (p5_buf_counter + 1) mod 64;
                        WHEN 14 =>
                            ip_pkt_len <= UNSIGNED(ip_pkt_len) +
                                UNSIGNED(p5_data_in(5)) + 20;
                            buf(TO_INTEGER(p5_buf_counter)) <= p5_data_in(5);
                            valid_buf(TO_INTEGER(p5_buf_counter)) <= '1';
                            p6_chk_accum_sig <= p5_chk_accum_sig + UNSIGNED(
                                ip_pkt_len) + UNSIGNED(p5_data_in(5)) + 20;
                            ip_pkt_len_valid <= '1';
                            p6_buf_counter <= (p5_buf_counter + 1) mod 64;
                        WHEN OTHERS =>
                            buf(TO_INTEGER(p5_buf_counter)) <= p5_data_in(5);
                            valid_buf(TO_INTEGER(p5_buf_counter)) <= '1';
                            p6_buf_counter <= (p5_buf_counter + 1) mod 64;
                    END CASE;
                END IF;

                -- Start Stage 6 of Pipeline
                IF p6_data_in_valid(6) = '1' THEN
                    p7_chk_accum_sig <= p6_chk_accum_sig;
                    CASE TO_INTEGER(p6_len_read_sig) IS
                    -- Source Address
                        WHEN 0 =>
                            ip_addr_src_hi(15 DOWNTO 8) <= p6_data_in(6);
                        WHEN 1 =>
                            ip_addr_src_hi(7 DOWNTO 0) <= p6_data_in(6);
                            -- Probably need to convert ip_addr_src_hi, etc. to UNSIGNED
                        WHEN 2 =>
                            p7_chk_accum_sig <= p6_chk_accum_sig + UNSIGNED(ip_addr_src_hi);
                            ip_addr_src_lo(15 DOWNTO 8) <= p6_data_in(6);
                        WHEN 3 =>
                            ip_addr_src_lo(7 DOWNTO 0) <= p6_data_in(6);
                        -- Destination Address
                        WHEN 4 =>
                            p7_chk_accum_sig <= p6_chk_accum_sig + UNSIGNED(ip_addr_src_lo);
                            ip_addr_dst_hi(15 DOWNTO 8) <= p6_data_in(6);
                        WHEN 5 =>
                            ip_addr_dst_hi(7 DOWNTO 0) <= p6_data_in(6);
                        WHEN 6 =>
                            p7_chk_accum_sig <= p6_chk_accum_sig + UNSIGNED(ip_addr_dst_hi);
                            ip_addr_dst_lo(15 DOWNTO 8) <= p6_data_in(6);
                        WHEN 7 =>
                            ip_addr_dst_lo(7 DOWNTO 0) <= p6_data_in(6);
                        -- Protocol
                        WHEN 8 =>
                            p7_chk_accum_sig <= p6_chk_accum_sig + UNSIGNED(ip_addr_dst_lo);
                            IF p6_data_in(6) /= UDP_PROTO THEN
                                p6_data_in_err <= '1'; --Insert new error here
                            END IF;
                        WHEN 13 =>
                            ip_pkt_len(15 DOWNTO 8) <= UNSIGNED(p6_data_in(6));
                            buf(TO_INTEGER(p6_buf_counter)) <= p6_data_in(6);
                            valid_buf(TO_INTEGER(p6_buf_counter)) <= '1';
                            p7_buf_counter <= (p6_buf_counter + 1) mod 64;
                        WHEN 14 =>
                            ip_pkt_len <= UNSIGNED(ip_pkt_len) +
                                UNSIGNED(p6_data_in(6)) + 20;
                            buf(TO_INTEGER(p6_buf_counter)) <= p6_data_in(6);
                            valid_buf(TO_INTEGER(p6_buf_counter)) <= '1';
                            p7_chk_accum_sig <= p6_chk_accum_sig + UNSIGNED(
                                ip_pkt_len) + UNSIGNED(p6_data_in(6)) + 20;
                            ip_pkt_len_valid <= '1';
                            p7_buf_counter <= (p6_buf_counter + 1) mod 64;
                        WHEN OTHERS =>
                            buf(TO_INTEGER(p6_buf_counter)) <= p6_data_in(6);
                            valid_buf(TO_INTEGER(p6_buf_counter)) <= '1';
                            p7_buf_counter <= (p6_buf_counter + 1) mod 64;
                    END CASE;
                END IF;

                -- Start Stage 7 of Pipeline
                IF p7_data_in_valid(7) = '1' THEN
                    p8_chk_accum_sig <= p8_chk_accum_sig + p7_chk_accum_sig;
                    CASE TO_INTEGER(p7_len_read_sig) IS
                    -- Source Address
                        WHEN 0 =>
                            ip_addr_src_hi(15 DOWNTO 8) <= p7_data_in(7);
                        WHEN 1 =>
                            ip_addr_src_hi(7 DOWNTO 0) <= p7_data_in(7);
                            -- Probably need to convert ip_addr_src_hi, etc. to UNSIGNED
                        WHEN 2 =>
                            p8_chk_accum_sig <= p8_chk_accum_sig + p7_chk_accum_sig + UNSIGNED(ip_addr_src_hi);
                            ip_addr_src_lo(15 DOWNTO 8) <= p7_data_in(7);
                        WHEN 3 =>
                            ip_addr_src_lo(7 DOWNTO 0) <= p7_data_in(7);
                        -- Destination Address
                        WHEN 4 =>
                            p8_chk_accum_sig <= p8_chk_accum_sig + p7_chk_accum_sig + UNSIGNED(ip_addr_src_lo);
                            ip_addr_dst_hi(15 DOWNTO 8) <= p7_data_in(7);
                        WHEN 5 =>
                            ip_addr_dst_hi(7 DOWNTO 0) <= p7_data_in(7);
                        WHEN 6 =>
                            p8_chk_accum_sig <= p8_chk_accum_sig + p7_chk_accum_sig + UNSIGNED(ip_addr_dst_hi);
                            ip_addr_dst_lo(15 DOWNTO 8) <= p7_data_in(7);
                        WHEN 7 =>
                            ip_addr_dst_lo(7 DOWNTO 0) <= p7_data_in(7);
                        -- Protocol
                        WHEN 8 =>
                            p8_chk_accum_sig <= p8_chk_accum_sig + p7_chk_accum_sig + UNSIGNED(ip_addr_dst_lo);
                            IF p7_data_in(7) /= UDP_PROTO THEN
                                p7_data_in_err <= '1'; --Insert new error here
                            END IF;
                        WHEN 13 =>
                            ip_pkt_len(15 DOWNTO 8) <= UNSIGNED(p7_data_in(7));
                            buf(TO_INTEGER(p7_buf_counter)) <= p7_data_in(7);
                            valid_buf(TO_INTEGER(p7_buf_counter)) <= '1';
                        WHEN 14 =>
                            ip_pkt_len <= UNSIGNED(ip_pkt_len) +
                                UNSIGNED(p7_data_in(7)) + 20;
                            buf(TO_INTEGER(p7_buf_counter)) <= p7_data_in(7);
                            valid_buf(TO_INTEGER(p7_buf_counter)) <= '1';
                            p8_chk_accum_sig <= p8_chk_accum_sig + p7_chk_accum_sig + UNSIGNED(
                                ip_pkt_len) + UNSIGNED(p7_data_in(7)) + 20;
                            ip_pkt_len_valid <= '1';
                        WHEN OTHERS =>
                            buf(TO_INTEGER(p7_buf_counter)) <= p7_data_in(7);
                            valid_buf(TO_INTEGER(p7_buf_counter)) <= '1';

                            --Enable for Stage 8
                            IF p8_enable = '0' THEN
                                p8_enable <= '1';
                                p8_chk_accum_sig <= p8_chk_accum_sig + x"8511";
                            END IF;
                    END CASE;
                END IF;

                -- Start Stage 8 of Pipeline (Output)
                IF p8_enable = '1' THEN
                    CASE TO_INTEGER(p8_output_counter) IS
                        WHEN 0 =>
                            p8_data_in(0) <= ip_hdr_len(15 DOWNTO 8);
                            p8_data_in(1) <= ip_hdr_len(7 DOWNTO 0);
                            p8_data_in(2) <= STD_LOGIC_VECTOR(ip_pkt_len(15 DOWNTO 8));
                            p8_data_in(3) <= STD_LOGIC_VECTOR(ip_pkt_len(7 DOWNTO 0));
                            p8_data_in(4) <= ip_id(15 DOWNTO 8);
                            p8_data_in(5) <= ip_id(7 DOWNTO 0);
                            p8_data_in(6) <= ip_flag_frag(15 DOWNTO 8);
                            p8_data_in(7) <= ip_flag_frag(7 DOWNTO 0);
                            -- Checksum is no more than 17 bits after one overflow
                            IF p8_chk_accum_sig(20 DOWNTO 16) /= "00000" THEN
                                ip_hdr_chk <= "0"&p8_chk_accum_sig(15 DOWNTO 0) +
                                    p8_chk_accum_sig(20 DOWNTO 16);
                            ELSE
                                ip_hdr_chk <= "0"&p8_chk_accum_sig(15 DOWNTO 0);
                            END IF;
                            p0_chk_accum_sig <= (OTHERS => '0');
                            p1_chk_accum_sig <= (OTHERS => '0');
                            p2_chk_accum_sig <= (OTHERS => '0');
                            p3_chk_accum_sig <= (OTHERS => '0');
                            p4_chk_accum_sig <= (OTHERS => '0');
                            p5_chk_accum_sig <= (OTHERS => '0');
                            p6_chk_accum_sig <= (OTHERS => '0');
                            p7_chk_accum_sig <= (OTHERS => '0');
                            p8_chk_accum_sig <= (OTHERS => '0');
                            p8_data_in_start <= '1';
                            p8_data_in_valid <= (OTHERS => '1');
                            p8_output_counter <= p8_output_counter + 1;
                        WHEN 1 =>
                            p8_data_in(0) <= ip_ttl_proto(15 DOWNTO 8);
                            p8_data_in(1) <= ip_ttl_proto(7 DOWNTO 0);
                            -- Efficient checksum assigning without variables
                            IF ip_hdr_chk(16) = '1' AND
                                ip_hdr_chk(7 DOWNTO 0) = x"FF" THEN
                                p8_data_in(2) <=  STD_LOGIC_VECTOR(x"FF" - (ip_hdr_chk(15 DOWNTO 8) + 1));
                                p8_data_in(3) <= x"FF";
                            ELSE
                                p8_data_in(2) <= STD_LOGIC_VECTOR(x"FF" - ip_hdr_chk(15 DOWNTO 8));
                                p8_data_in(3) <= STD_LOGIC_VECTOR(x"FF" - (ip_hdr_chk(7 DOWNTO 0) + 1));
                            END IF;
                            ip_hdr_chk <= (OTHERS => '0');
                            p8_data_in(4) <= ip_addr_src_hi(15 DOWNTO 8);
                            p8_data_in(5) <= ip_addr_src_hi(7 DOWNTO 0);
                            p8_data_in(6) <= ip_addr_src_lo(15 DOWNTO 8);
                            p8_data_in(7) <= ip_addr_src_lo(7 DOWNTO 0);
                            p8_data_in_start <= '0';
                            p8_data_in_valid <= (OTHERS => '1');
                            p8_output_counter <= p8_output_counter + 1;
                        WHEN 2 =>
                            p8_data_in(0) <= ip_addr_dst_hi(15 DOWNTO 8);
                            p8_data_in(1) <= ip_addr_dst_hi(7 DOWNTO 0);
                            p8_data_in(2) <= ip_addr_dst_lo(15 DOWNTO 8);
                            p8_data_in(3) <= ip_addr_dst_lo(7 DOWNTO 0);
                            p8_data_in_valid(3 DOWNTO 0) <= (OTHERS => '1');
                            IF valid_buf(0) = '1' THEN
                                p8_data_in(4) <= buf(0);
                                p8_data_in_valid(4) <= '1';
                                valid_buf(0) <= '0';
                                buf(0) <= x"00";
                            END IF;
                            IF valid_buf(1) = '1' THEN
                                p8_data_in(5) <= buf(1);
                                p8_data_in_valid(5) <= '1';
                                valid_buf(1) <= '0';
                                buf(1) <= x"00";
                            END IF;
                            IF valid_buf(2) = '1' THEN
                                p8_data_in(6) <= buf(2);
                                p8_data_in_valid(6) <= '1';
                                valid_buf(2) <= '0';
                                buf(2) <= x"00";
                            END IF;
                            IF valid_buf(3) = '1' THEN
                                p8_data_in(7) <= buf(3);
                                p8_data_in_valid(7) <= '1';
                                valid_buf(3) <= '0';
                                buf(3) <= x"00";
                            END IF;
                            --'0' hasn't been assigned to valid_buf yet
                            IF valid_buf(3) <= '1' THEN
                                buf_out_counter <= "000100";
                            ELSIF valid_buf(2) <= '1' THEN
                                buf_out_counter <= "000011";
                            ELSIF valid_buf(1) <= '1' THEN
                                buf_out_counter <= "000010";
                            ELSIF valid_buf(0) <= '1' THEN
                                buf_out_counter <= "000001";
                            END IF;
                            IF valid_buf(3) <= '0' THEN
                                p8_output_counter <= p8_output_counter + 2;
                                p8_data_in_end <= '1';
                                buf <= (OTHERS => x"00");
                                valid_buf <= (OTHERS => '0');
                                p0_buf_counter <= (OTHERS => '0');
                                buf_out_counter <= (OTHERS => '0');
                            ELSE
                                p8_output_counter <= p8_output_counter + 1;
                            END IF;
                        WHEN 3 =>
                            -- TODO: handle slow data? (buffer shouldn't empty)
                            -- Tuned for speed efficiency, otherwise use variables
                            p8_data_in(0) <= buf(TO_INTEGER(buf_out_counter));
                            p8_data_in(1) <= buf((TO_INTEGER(buf_out_counter)
                                +1) mod 64);
                            p8_data_in(2) <= buf((TO_INTEGER(buf_out_counter)
                                +2) mod 64);
                            p8_data_in(3) <= buf((TO_INTEGER(buf_out_counter)
                                +3) mod 64);
                            p8_data_in(4) <= buf((TO_INTEGER(buf_out_counter)
                                +4) mod 64);
                            p8_data_in(5) <= buf((TO_INTEGER(buf_out_counter)
                                +5) mod 64);
                            p8_data_in(6) <= buf((TO_INTEGER(buf_out_counter)
                                +6) mod 64);
                            p8_data_in(7) <= buf((TO_INTEGER(buf_out_counter)
                                +7) mod 64);

                            p8_data_in_valid(0) <= valid_buf(TO_INTEGER(
                                buf_out_counter));
                            p8_data_in_valid(1) <= valid_buf((TO_INTEGER(
                                buf_out_counter)+1) mod 64);
                            p8_data_in_valid(2) <= valid_buf((TO_INTEGER(
                                buf_out_counter)+2) mod 64);
                            p8_data_in_valid(3) <= valid_buf((TO_INTEGER(
                                buf_out_counter)+3) mod 64);
                            p8_data_in_valid(4) <= valid_buf((TO_INTEGER(
                                buf_out_counter)+4) mod 64);
                            p8_data_in_valid(5) <= valid_buf((TO_INTEGER(
                                buf_out_counter)+5) mod 64);
                            p8_data_in_valid(6) <= valid_buf((TO_INTEGER(
                                buf_out_counter)+6) mod 64);
                            p8_data_in_valid(7) <= valid_buf((TO_INTEGER(
                                buf_out_counter)+7) mod 64);

                            IF valid_buf((TO_INTEGER(buf_out_counter)+7) mod 64
                                ) = '0' THEN
                                p8_output_counter <= p8_output_counter + 1;
                                p8_data_in_end <= '1';
                                buf <= (OTHERS => x"00");
                                valid_buf <= (OTHERS => '0');
                                p0_buf_counter <= (OTHERS => '0');
                                buf_out_counter <= (OTHERS => '0');
                            ELSE
                                buf_out_counter <= (buf_out_counter + 8) ;
                            END IF;

                            buf(TO_INTEGER(buf_out_counter)) <= x"00";
                            buf((TO_INTEGER(buf_out_counter)+1) mod 64) <= x"00";
                            buf((TO_INTEGER(buf_out_counter)+2) mod 64) <= x"00";
                            buf((TO_INTEGER(buf_out_counter)+3) mod 64) <= x"00";
                            buf((TO_INTEGER(buf_out_counter)+4) mod 64) <= x"00";
                            buf((TO_INTEGER(buf_out_counter)+5) mod 64) <= x"00";
                            buf((TO_INTEGER(buf_out_counter)+6) mod 64) <= x"00";
                            buf((TO_INTEGER(buf_out_counter)+7) mod 64) <= x"00";

                            valid_buf(TO_INTEGER(buf_out_counter)) <= '0';
                            valid_buf((TO_INTEGER(buf_out_counter)+1) mod 64) <= '0';
                            valid_buf((TO_INTEGER(buf_out_counter)+2) mod 64) <= '0';
                            valid_buf((TO_INTEGER(buf_out_counter)+3) mod 64) <= '0';
                            valid_buf((TO_INTEGER(buf_out_counter)+4) mod 64) <= '0';
                            valid_buf((TO_INTEGER(buf_out_counter)+5) mod 64) <= '0';
                            valid_buf((TO_INTEGER(buf_out_counter)+6) mod 64) <= '0';
                            valid_buf((TO_INTEGER(buf_out_counter)+7) mod 64) <= '0';

                        WHEN OTHERS =>
                            p8_enable <= '0';
                            p8_output_counter <= (OTHERS => '0');
                            p8_data_in_valid <= (OTHERS => '0');
                            p8_data_in_end <= '0';
                            p8_data_in_err <= '0';
                    END CASE;
                END IF;

                p1_data_in <= p0_data_in;
                p2_data_in <= p1_data_in;
                p3_data_in <= p2_data_in;
                p4_data_in <= p3_data_in;
                p5_data_in <= p4_data_in;
                p6_data_in <= p5_data_in;
                p7_data_in <= p6_data_in;

                p1_data_in_valid <= p0_data_in_valid;
                p2_data_in_valid <= p1_data_in_valid;
                p3_data_in_valid <= p2_data_in_valid;
                p4_data_in_valid <= p3_data_in_valid;
                p5_data_in_valid <= p4_data_in_valid;
                p6_data_in_valid <= p5_data_in_valid;
                p7_data_in_valid <= p6_data_in_valid;

                p1_data_in_end <= p0_data_in_end;
                p2_data_in_end <= p1_data_in_end;
                p3_data_in_end <= p2_data_in_end;
                p4_data_in_end <= p3_data_in_end;
                p5_data_in_end <= p4_data_in_end;
                p6_data_in_end <= p5_data_in_end;
                p7_data_in_end <= p6_data_in_end;
                --p8_data_in_end <= p7_data_in_end;

                p1_data_in_err <= p0_data_in_err;
                p2_data_in_err <= p1_data_in_err;
                p3_data_in_err <= p2_data_in_err;
                p4_data_in_err <= p3_data_in_err;
                p5_data_in_err <= p4_data_in_err;
                p6_data_in_err <= p5_data_in_err;
                p7_data_in_err <= p6_data_in_err;
                --p8_data_in_err <= p7_data_in_err;

                --p1_chk_accum_sig <= p0_chk_accum_sig;
                --p2_chk_accum_sig <= p1_chk_accum_sig;
                --p3_chk_accum_sig <= p2_chk_accum_sig;
                --p4_chk_accum_sig <= p3_chk_accum_sig;
                --p5_chk_accum_sig <= p4_chk_accum_sig;
                --p6_chk_accum_sig <= p5_chk_accum_sig;
                --p7_chk_accum_sig <= p6_chk_accum_sig;
                --p8_chk_accum_sig <= p7_chk_accum_sig;
            END IF;
        END IF;
    END PROCESS;

    -- Output signal wiring
    gen_out_data: FOR i IN 0 TO width - 1 GENERATE
        Data_out((i + 1) * 8 - 1 DOWNTO i * 8) <= p8_data_in(i);
    END GENERATE;
    Data_out_valid <= p8_data_in_valid;
    Data_out_start <= p8_data_in_start;
    Data_out_end <= p8_data_in_end;
    Data_out_err <= p8_data_in_err;
END ARCHITECTURE;
