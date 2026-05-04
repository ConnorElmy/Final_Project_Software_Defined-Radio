----------------------------------------------------------------------------------
-- BASK_Demodulator.vhd
--
-- Converted from MATLAB prototype stage-for-stage.
-- Variable names match the MATLAB code where VHDL syntax permits.
--
-- Pipeline:
--   Stage 1 : Clock Divider        (MATLAB: Fs = audioread(...))
--   Stage 2 : BPF                  (MATLAB: filter(b_BPF, a_BPF, signal))
--   Stage 3 : Rectifier            (MATLAB: rectified = abs(filteredSignal))
--   Stage 4 : Moving Average LPF   (MATLAB: envelope = conv(rectified, kernel))
--   Stage 5 : Decimation           (MATLAB: envelopeSample = envelope(1:M:end))
--   Stage 6 : Threshold            (MATLAB: bitsRaw = envelopeNormalised > 0.60)
--   Stage 7 : Majority Vote        (MATLAB: recoveredBits majority loop)
--   Stage 8 : Byte Decode          (MATLAB: bi2de(asciiByte, 'left-msb'))
--
-- Target : Digilent Cmod A7-35T (Spartan-7 XC7S25)
-- Clock  : 12 MHz onboard oscillator
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity BASK_Demodulator is
    Port (
        clk_12MHz       : in  std_logic;
        reset           : in  std_logic;
        
        -- 12-bit signed sample arriving from ADC each sample_tick
        mcp_sck  : out std_logic;
        mcp_cs   : out std_logic;
        mcp_miso : in  std_logic;
    
        -- Decoded ASCII character output
        char_out        : out std_logic_vector(7 downto 0);
        char_valid      : out std_logic;    -- Pulses high for one clock when char_out is valid
        -- Debug outputs (match modulator debug pins)
        bit_out         : out std_logic;    -- Recovered bit stream
        sample_tick_out : out std_logic;     -- ~141 kHz sample strobe
        bit_pulse_out : out std_logic  -- One-clock pulse per recovered bit
    );
end BASK_Demodulator;

architecture Behavioral of BASK_Demodulator is

    -----------------------------------------------------------------------
    -- CONSTANTS
    -- All values derived from the same parameters as the MATLAB prototype:
    --   Fc = 2200 Hz, BitRate = 2 bps, oversampleRate = 16, bitsPerChar = 8
    -- Fs = 12 MHz / (CLK_DIV+1) = 12000000 / 85 = 141,176 Hz
    -----------------------------------------------------------------------

    --ADC
    constant SPI_CLK_DIV : integer := 4;  -- SCK = 12mHz/(5*2)
-- SCK = 12MHz/(2*3) = 2 MHz


    -- Stage 1: clock divider
    -- 12 MHz / 85 = 141,176 Hz  (matches modulator clock divider)
    constant CLK_DIV          : integer := 84;

    -- Stage 4: moving average window
    -- MATLAB: window = Fs/Fc = 141176/2200 = 64.17 -> 64 (power of 2)
    -- MATLAB: windowPow2 = 64,  shift_amount = 6
    constant LPF_WINDOW       : integer := 64;
    constant LPF_SHIFT        : integer := 6;   -- log2(64): right-shift replaces division

    -- Stage 5: decimation
    -- MATLAB: samplesPerBit = round(Fs/bitRate) = round(141176/2) = 70588
    -- MATLAB: M = samplesPerBit / oversampleRate = 70588/16 = 4412 (rounded)
    constant SAMPLES_PER_BIT  : integer := 70588;
    constant OVERSAMPLE        : integer := 16;
    constant DECIMATE_M        : integer := 4412;

    -- Stage 6: threshold
    -- MATLAB normalises 0->1 then compares > 0.60.
    -- In VHDL we compare against a fixed integer (no normalisation needed).
    -- After rectify+LPF: mean(|A*sin()|) over full cycle = A*(2/pi)
    --   High envelope = mHigh * (2/pi) * 2047 = 1.0  * 0.637 * 2047 = 1304
    --   Low  envelope = mLow  * (2/pi) * 2047 = 0.2  * 0.637 * 2047 =  261
    --   Threshold (midpoint) = (1304 + 261) / 2 = 782
    constant THRESHOLD        : signed(11 downto 0) := to_signed(782, 12);

    -----------------------------------------------------------------------
    -- BPF Q15 COEFFICIENTS
    --
    -- MATLAB generates these with:
    --   Fs  = 140800;  Fc = 2200;  BW = 1000;
    --   [b_BPF, a_BPF] = butter(2, [(Fc-BW/2) (Fc+BW/2)] / (Fs/2), 'bandpass');
    --   sos = tf2sos(b_BPF, a_BPF);
    --   % sos rows: [b0 b1 b2 a0 a1 a2], a0 is always 1 (implicit in VHDL)
    --   % b1 = sos(i,2) is always 0 for a bandpass biquad (omitted below)
    --   % Quantise to Q15: multiply by 32768 and round
    --   fprintf('B1_0=%d  B1_2=%d  A1_1=%d  A1_2=%d\n', ...
    --     round(sos(1,1)*32768), round(sos(1,3)*32768), ...
    --     round(sos(1,5)*32768), round(sos(1,6)*32768));
    --   fprintf('B2_0=%d  B2_2=%d  A2_1=%d  A2_2=%d\n', ...
    --     round(sos(2,1)*32768), round(sos(2,3)*32768), ...
    --     round(sos(2,5)*32768), round(sos(2,6)*32768));
    --
    -- !! REPLACE the placeholder values below with your MATLAB output !!
    -- Note: B_2 = -B_0 always holds for a BPF biquad (symmetric numerator)
    -----------------------------------------------------------------------
    constant B1_0 : signed(15 downto 0) := to_signed(16,     16);  -- REPLACE
    constant B1_2 : signed(15 downto 0) := to_signed(-16,    16);  -- REPLACE (= -B1_0)
    constant A1_1 : signed(15 downto 0) := to_signed(-63944, 16);  -- REPLACE
    constant A1_2 : signed(15 downto 0) := to_signed(31586,  16);  -- REPLACE

    constant B2_0 : signed(15 downto 0) := to_signed(32767,     16);  -- REPLACE
    constant B2_2 : signed(15 downto 0) := to_signed(-32767,    16);  -- REPLACE (= -B2_0)
    constant A2_1 : signed(15 downto 0) := to_signed(-64472, 16);  -- REPLACE
    constant A2_2 : signed(15 downto 0) := to_signed(31915,  16);  -- REPLACE

    -----------------------------------------------------------------------
    -- INTERNAL SIGNALS
    -----------------------------------------------------------------------

    --ADC
    type spi_state_t is (SPI_IDLE, SPI_CS_LOW, SPI_TRANSFER, SPI_CS_HIGH);
signal spi_state    : spi_state_t := SPI_IDLE;
signal spi_clk_cnt  : integer range 0 to SPI_CLK_DIV := 0;
signal spi_clk_reg  : std_logic := '0';
signal spi_bit_cnt  : integer range 0 to 13 := 0;
signal spi_shift    : std_logic_vector(12 downto 0) := (others => '0');
signal spi_cs_reg   : std_logic := '1';
signal adc_sample   : signed(11 downto 0) := (others => '0');
-- (Remove adc_sample from entity ports - it is now generated internally)


    --For recieved message debugging, before the LCD controller is implemented.
    signal bit_valid_prev : std_logic := '0';

    -- Stage 1: clock divider
    signal clk_div_cnt  : integer range 0 to CLK_DIV := 0;
    signal sample_tick  : std_logic := '0';

    -- Stage 2: BPF
    -- State registers held at full Q-product precision (28 bits).
    -- 16-bit coeff * 12-bit input = 28-bit product (signed(27 downto 0)).
    -- Output y[n] = product bits [26:15] after Q15 descale (>> 15 = 12-bit result).
    signal bpf1_s1, bpf1_s2 : signed(27 downto 0) := (others => '0');
    signal bpf2_s1, bpf2_s2 : signed(27 downto 0) := (others => '0');
    signal bpf1_out          : signed(11 downto 0) := (others => '0');
    signal bpf_out           : signed(11 downto 0) := (others => '0');

    -- Stage 3: rectifier
    -- MATLAB: rectified = abs(filteredSignal)
    signal rectified : signed(11 downto 0) := (others => '0');

    -- Stage 4: moving average LPF
    -- MATLAB: envelope = conv(rectified, ones(1,64)/64, 'same')
    -- VHDL: circular buffer (delay_line) + running_sum register
    -- running_sum width: 12 bits + 6 overflow bits = 18 bits
    type delay_line_t is array (0 to LPF_WINDOW-1) of signed(11 downto 0);
    signal delay_line  : delay_line_t := (others => (others => '0'));
    signal dl_ptr      : integer range 0 to LPF_WINDOW-1 := 0;
    signal running_sum : signed(17 downto 0) := (others => '0');
    signal envelope    : signed(11 downto 0) := (others => '0');

    -- Stage 5: decimation
    -- MATLAB: envelopeSample = envelope(1:M:end)
    signal dec_cnt  : integer range 0 to DECIMATE_M-1 := 0;
    signal dec_tick : std_logic := '0';
    signal envelopeSample : signed(11 downto 0) := (others => '0');

    -- Stage 6: threshold
    -- MATLAB: bitsRaw = envelopeNormalised > threshold
    signal bitsRaw : std_logic := '0';

    -- Stage 7: majority vote (16x UART oversampling)
    -- MATLAB: majoritySum = sum(windowSlice); recoveredBits(i) = majoritySum > 8
    -- VHDL: 4-bit counter (0-15) + 5-bit accumulator, no multipliers
    signal vote_cnt      : integer range 0 to OVERSAMPLE-1 := 0;
    signal vote_sum      : integer range 0 to OVERSAMPLE   := 0;
    signal bit_valid     : std_logic := '0';
    signal recoveredBit  : std_logic := '0';

    -- Stage 8: byte decode
    -- MATLAB: character = bi2de(asciiByte, 'left-msb')
    -- VHDL: 8-bit shift register, MSB first (matches modulator)
    signal byte_sr  : std_logic_vector(7 downto 0) := (others => '0');
    signal bit_cnt  : integer range 0 to 7 := 0;

begin

    -- Route internal signals to debug/output ports
    sample_tick_out <= sample_tick;
    bit_out         <= recoveredBit;
    bit_pulse_out <= bit_valid and not bit_valid_prev; --Pulse high for 1 clock when a new bit is recovered
    -----------------------------------------------------------------------
    -- STAGE 1: CLOCK DIVIDER
    -- MATLAB equivalent: Fs is read from the WAV header by audioread().
    -- On the FPGA we generate sample_tick at the same rate as the modulator:
    --   12 MHz / 85 = 141,176 Hz
    -- Identical to the clock divider process in BASK_Modulator.vhd.
    -----------------------------------------------------------------------
    
    pulse_proc: process(clk_12MHz)
    begin
       if rising_edge(clk_12MHz) then
            bit_valid_prev <= bit_valid;
        end if;
    end process;
    
    clk_div_proc: process(clk_12MHz, reset)
    begin
        if reset = '1' then
            clk_div_cnt <= 0;
            sample_tick <= '0';
        elsif rising_edge(clk_12MHz) then
            if clk_div_cnt = CLK_DIV then
                clk_div_cnt <= 0;
                sample_tick <= '1';
            else
                clk_div_cnt <= clk_div_cnt + 1;
                sample_tick <= '0';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- STAGE 2: BANDPASS FILTER (BPF)
    -- MATLAB equivalent:
    --   [b_BPF, a_BPF] = butter(2, [f_low, f_high], 'bandpass')
    --   filteredSignal  = filter(b_BPF, a_BPF, signal)
    --
    -- Implementation: two cascaded biquads, Direct Form II Transposed.
    -- This structure pipelines well and only needs two delay registers per
    -- biquad rather than four (Direct Form I).
    --
    -- Biquad difference equations (b1 = 0 for all BPF biquads):
    --   y[n]  = (b0*x[n]  + s1[n-1]) >> 15      Q15 descale
    --   s1[n] = -a1*y[n]  + s2[n-1]              (b1*x = 0, omitted)
    --   s2[n] =  b2*x[n]  - a2*y[n]
    --
    -- Bit widths:
    --   Coefficient (Q15):   signed(15 downto 0)   16 bits
    --   Input x / output y:  signed(11 downto 0)   12 bits
    --   Product (16*12):     signed(27 downto 0)   28 bits
    --   State s1, s2:        signed(27 downto 0)   28 bits (product scale)
    --   Q15 descale: take bits [26:15] of 28-bit sum -> 12-bit output
    -----------------------------------------------------------------------
    bpf_proc: process(clk_12MHz, reset)
        variable y_sum_v : signed(27 downto 0);
        variable y1_v    : signed(11 downto 0);
        variable y2_v    : signed(11 downto 0);
    begin
        if reset = '1' then
            bpf1_s1  <= (others => '0');
            bpf1_s2  <= (others => '0');
            bpf2_s1  <= (others => '0');
            bpf2_s2  <= (others => '0');
            bpf1_out <= (others => '0');
            bpf_out  <= (others => '0');
        elsif rising_edge(clk_12MHz) then
            if sample_tick = '1' then

                -- ---- Biquad 1: input = adc_sample ----
                -- y1[n] = (B1_0 * adc_sample + s1[n-1]) >> 15
                y_sum_v  := B1_0 * adc_sample + bpf1_s1;
                y1_v     := y_sum_v(26 downto 15);          -- >> 15, 12-bit result

                -- s1[n] = -A1_1 * y1 + s2[n-1]
                bpf1_s1  <= -(A1_1 * y1_v) + bpf1_s2;

                -- s2[n] = B1_2 * adc_sample - A1_2 * y1
                bpf1_s2  <= B1_2 * adc_sample - A1_2 * y1_v;

                bpf1_out <= y1_v;   -- Register output for use by biquad 2 next tick

                -- ---- Biquad 2: input = bpf1_out (registered, one tick delay) ----
                -- y2[n] = (B2_0 * bpf1_out + s1[n-1]) >> 15
                y_sum_v  := B2_0 * bpf1_out + bpf2_s1;
                y2_v     := y_sum_v(26 downto 15);

                -- s1[n] = -A2_1 * y2 + s2[n-1]
                bpf2_s1  <= -(A2_1 * y2_v) + bpf2_s2;

                -- s2[n] = B2_2 * bpf1_out - A2_2 * y2
                bpf2_s2  <= B2_2 * bpf1_out - A2_2 * y2_v;

                bpf_out  <= y2_v;

            end if;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- STAGE 3: RECTIFIER
    -- MATLAB equivalent: rectified = abs(filteredSignal)
    --
    -- VHDL: inspect the sign bit. If bpf_out is negative (sign bit = '1'),
    -- negate it (2's complement inversion). Otherwise pass through.
    -- Zero LUT cost beyond a comparator and XOR tree.
    -----------------------------------------------------------------------
    rect_proc: process(clk_12MHz, reset)
    begin
        if reset = '1' then
            rectified <= (others => '0');
        elsif rising_edge(clk_12MHz) then
            if sample_tick = '1' then
                if bpf_out(11) = '1' then   -- Sign bit set = negative
                    rectified <= -bpf_out;
                else
                    rectified <= bpf_out;
                end if;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- STAGE 4: MOVING AVERAGE LOW-PASS FILTER
    -- MATLAB equivalent:
    --   kernel   = ones(1, windowPow2) / windowPow2   % 64 ones / 64
    --   envelope = conv(rectified, kernel, 'same')
    --
    -- VHDL implements the same result as a sliding-window running sum:
    --   running_sum[n] = running_sum[n-1] + new_sample - oldest_sample
    --   envelope[n]    = running_sum[n] >> LPF_SHIFT      (divide by 64)
    --
    -- delay_line is a circular buffer of depth LPF_WINDOW (64).
    -- dl_ptr always points to the oldest sample (about to be evicted).
    --
    -- running_sum width: max value = 64 * 2047 = 130,048
    --   ceil(log2(130049)) = 17 bits + 1 sign = 18 bits total.
    -- envelope = running_sum(17 downto 6) -> 12 bits (>> 6 = divide by 64).
    -----------------------------------------------------------------------
    lpf_proc: process(clk_12MHz, reset)
        variable oldest : signed(11 downto 0);
    begin
        if reset = '1' then
            delay_line  <= (others => (others => '0'));
            dl_ptr      <= 0;
            running_sum <= (others => '0');
            envelope    <= (others => '0');
        elsif rising_edge(clk_12MHz) then
            if sample_tick = '1' then

                oldest      := delay_line(dl_ptr);          -- Fetch oldest sample

                running_sum <= running_sum                  -- Slide window:
                             + resize(rectified, 18)        --   add newest sample
                             - resize(oldest,    18);       --   subtract evicted sample

                delay_line(dl_ptr) <= rectified;            -- Overwrite oldest slot

                if dl_ptr = LPF_WINDOW - 1 then            -- Advance circular pointer
                    dl_ptr <= 0;
                else
                    dl_ptr <= dl_ptr + 1;
                end if;

                -- Divide by 64: arithmetic right shift 6 places via bit slice
                -- MATLAB: equivalent to running_sum / windowPow2
                envelope <= running_sum(17 downto 6);       -- bits[17:6] = >> 6

            end if;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- STAGE 5: DECIMATION
    -- MATLAB equivalent:
    --   M = samplesPerBit / oversampleRate   % = 4412
    --   envelopeSample = envelope(1:M:end)
    --
    -- Every DECIMATE_M sample_ticks, latch envelope and fire dec_tick.
    -- Result: 16 samples per bit period (16x UART oversampling rate).
    -- dec_tick fires at 141176/4412 = 32 Hz (= bitRate * oversampleRate).
    -----------------------------------------------------------------------
    dec_proc: process(clk_12MHz, reset)
    begin
        if reset = '1' then
            dec_cnt       <= 0;
            dec_tick      <= '0';
            envelopeSample <= (others => '0');
        elsif rising_edge(clk_12MHz) then
            dec_tick <= '0';                                -- Default: no tick
            if sample_tick = '1' then
                if dec_cnt = DECIMATE_M - 1 then
                    dec_cnt        <= 0;
                    dec_tick       <= '1';                  -- Fires 16x per bit
                    envelopeSample <= envelope;             -- Latch current envelope
                else
                    dec_cnt <= dec_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- STAGE 6: THRESHOLD COMPARISON
    -- MATLAB equivalent:
    --   envelopeNormalised = envelopeSample / max(envelopeSample)  <- skipped
    --   bitsRaw = envelopeNormalised > threshold     % threshold = 0.60
    --
    -- In VHDL we skip normalisation (the AGC on the MAX9814 handles that
    -- in hardware). Instead compare against a fixed integer THRESHOLD = 782.
    -- This is a 12-bit signed comparator: zero LUTs beyond carry chain.
    -----------------------------------------------------------------------
    thresh_proc: process(clk_12MHz, reset)
    begin
        if reset = '1' then
            bitsRaw <= '0';
        elsif rising_edge(clk_12MHz) then
            if dec_tick = '1' then
                if envelopeSample > THRESHOLD then
                    bitsRaw <= '1';
                else
                    bitsRaw <= '0';
                end if;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- STAGE 7: MAJORITY VOTE (16x UART OVERSAMPLING)
    -- MATLAB equivalent:
    --   for i = 1:numPeriods
    --     windowSlice    = bitsRaw((i-1)*oversampleRate+1 : i*oversampleRate)
    --     majoritySum    = sum(windowSlice)
    --     recoveredBits  = (majoritySum > oversampleRate/2)
    --
    -- VHDL: 4-bit counter (vote_cnt, 0-15) counts the 16 dec_ticks per bit.
    --        5-bit accumulator (vote_sum, 0-16) sums bitsRaw over those 16.
    -- At vote_cnt = 15: compare vote_sum > 8, latch recoveredBit, reset.
    -- No multipliers, no dividers required.
    -----------------------------------------------------------------------
    vote_proc: process(clk_12MHz, reset)
        variable v_sum_next : integer range 0 to OVERSAMPLE;
    begin
        if reset = '1' then
            vote_cnt     <= 0;
            vote_sum     <= 0;
            bit_valid    <= '0';
            recoveredBit <= '0';
        elsif rising_edge(clk_12MHz) then
            bit_valid <= '0';                               -- Default: no new bit

            if dec_tick = '1' then
                -- Accumulate: 5-bit addition, no hardware multiplier needed
                if bitsRaw = '1' then
                    v_sum_next := vote_sum + 1;
                else
                    v_sum_next := vote_sum;
                end if;

                if vote_cnt = OVERSAMPLE - 1 then           -- End of 16-sample window
                    -- Majority decision: MATLAB equivalent of majoritySum > 8
                    if v_sum_next > OVERSAMPLE / 2 then
                        recoveredBit <= '1';
                    else
                        recoveredBit <= '0';
                    end if;
                    vote_sum  <= 0;                         -- Reset accumulator
                    vote_cnt  <= 0;
                    bit_valid <= '1';                       -- Pulse: new bit ready
                else
                    vote_sum <= v_sum_next;
                    vote_cnt <= vote_cnt + 1;
                end if;

            end if;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- STAGE 8: BYTE DECODE
    -- MATLAB equivalent:
    --   asciiByte  = recoveredBits((i-1)*bitsPerChar+1 : i*bitsPerChar)
    --   character  = bi2de(asciiByte, 'left-msb')
    --   decodedChars = [decodedChars char(character)]
    --
    -- VHDL: 8-bit shift register (byte_sr), MSB first (matches modulator).
    -- bit_cnt counts 0-7. When bit_cnt reaches 7, all 8 bits are in byte_sr
    -- and char_valid pulses high for one clock cycle.
    --
    -- Note: A full UART 8N1 implementation would also look for a start bit
    -- (logic '0' for one full bit period before data) and a stop bit
    -- (logic '1' after). Add that state machine here when the modulator
    -- is updated to include framing bits.
    -----------------------------------------------------------------------
    byte_proc: process(clk_12MHz, reset)
    begin
        if reset = '1' then
            byte_sr    <= (others => '0');
            bit_cnt    <= 0;
            char_out   <= (others => '0');
            char_valid <= '0';
        elsif rising_edge(clk_12MHz) then
            char_valid <= '0';                              -- Default: no new char
            if bit_valid = '1' then
                -- Shift register: MSB in first (bi2de 'left-msb' convention)
                byte_sr <= byte_sr(6 downto 0) & recoveredBit;

                if bit_cnt = 7 then                         -- All 8 bits received
                    char_out   <= byte_sr(6 downto 0) & recoveredBit; --OUTPUT THIS TO A PIN SO I CAN SEE IF THE DEMODULATION IS WORKING
                    char_valid <= '1';
                    bit_cnt    <= 0;
                else
                    bit_cnt <= bit_cnt + 1;
                end if;
            end if;
        end if;
    end process;
    
   spi_proc: process(clk_12MHz, reset)
    begin
        if reset = '1' then
            spi_state   <= SPI_IDLE;
            spi_clk_cnt <= 0;
            spi_clk_reg <= '0';
            spi_bit_cnt <= 0;
            spi_shift   <= (others => '0');
            spi_cs_reg  <= '1';
            adc_sample  <= (others => '0');
        elsif rising_edge(clk_12MHz) then
            case spi_state is

                -- Wait for sample_tick to trigger a new conversion
                when SPI_IDLE =>
                    spi_clk_reg <= '0';
                    spi_cs_reg  <= '1';
                    if sample_tick = '1' then
                        spi_state   <= SPI_CS_LOW;
                        spi_bit_cnt <= 0;
                        spi_shift   <= (others => '0');
                    end if;

                -- Hold CS low for one clock before SCK starts (setup time)
                when SPI_CS_LOW =>
                    spi_cs_reg  <= '0';
                    spi_clk_cnt <= 0;
                    spi_clk_reg <= '0';
                    spi_state   <= SPI_TRANSFER;
    
                -- Clock out 13 bits (1 null + 12 data), sampling MISO on rising SCK
                when SPI_TRANSFER =>
                    if spi_clk_cnt = SPI_CLK_DIV then
                        spi_clk_cnt <= 0;
                        spi_clk_reg <= not spi_clk_reg;  -- Toggle SCK
    
                        if spi_clk_reg = '0' then         -- Rising SCK edge: sample MISO
                            spi_shift <= spi_shift(11 downto 0) & mcp_miso;
                            if spi_bit_cnt = 12 then       -- 13 bits received (0 to 12)
                                spi_state <= SPI_CS_HIGH;
                            else
                                spi_bit_cnt <= spi_bit_cnt + 1;
                            end if;
                        end if;
                    else
                        spi_clk_cnt <= spi_clk_cnt + 1;
                    end if;

                -- CS high, latch result
                -- spi_shift(12) is the null bit (discard)
                -- spi_shift(11 downto 0) is the 12-bit unsigned result
                -- Convert to signed by subtracting midpoint (2048) so 0V = 0
                when SPI_CS_HIGH =>
                    spi_cs_reg <= '1';
                    adc_sample <= signed(spi_shift(11 downto 0)) - 2048;
                    spi_state  <= SPI_IDLE;

        end case;
    end if;
end process; 

-- Drive physical pins
mcp_sck <= spi_clk_reg when spi_cs_reg = '0' else '0';
mcp_cs  <= spi_cs_reg;

end Behavioral;