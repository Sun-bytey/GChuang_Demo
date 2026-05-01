module color_recognizer #(
    parameter SAMPLE_PAIRS = 16'd2048,
    parameter LATENCY_LIMIT = 17'd70000,
    parameter MIN_COLOR_COUNT = 16'd256,
    parameter HIGH_TH = 8'd180,
    parameter LOW_TH = 8'd60,
    parameter DARK_TH = 8'd45,
    parameter DIFF_TH = 8'd45
)(
    input             clk,
    input             rst_n,
    input             vs,
    input             de,
    input      [47:0] rgb_datax2,
    output reg [2:0]  color_id,
    output reg [4:0]  color_onehot,
    output reg        result_valid,
    output reg        latency_ok
);

localparam COLOR_UNKNOWN = 3'd0;
localparam COLOR_WHITE   = 3'd1;
localparam COLOR_BLACK   = 3'd2;
localparam COLOR_RED     = 3'd3;
localparam COLOR_BLUE    = 3'd4;
localparam COLOR_YELLOW  = 3'd5;

wire [7:0] r0 = rgb_datax2[47:40];
wire [7:0] g0 = rgb_datax2[39:32];
wire [7:0] b0 = rgb_datax2[31:24];
wire [7:0] r1 = rgb_datax2[23:16];
wire [7:0] g1 = rgb_datax2[15:8];
wire [7:0] b1 = rgb_datax2[7:0];

wire white0  = (r0 > HIGH_TH) && (g0 > HIGH_TH) && (b0 > HIGH_TH);
wire white1  = (r1 > HIGH_TH) && (g1 > HIGH_TH) && (b1 > HIGH_TH);
wire black0  = (r0 < DARK_TH) && (g0 < DARK_TH) && (b0 < DARK_TH);
wire black1  = (r1 < DARK_TH) && (g1 < DARK_TH) && (b1 < DARK_TH);
wire red0    = (r0 > HIGH_TH) && ({1'b0, r0} > ({1'b0, g0} + {1'b0, DIFF_TH})) && ({1'b0, r0} > ({1'b0, b0} + {1'b0, DIFF_TH}));
wire red1    = (r1 > HIGH_TH) && ({1'b0, r1} > ({1'b0, g1} + {1'b0, DIFF_TH})) && ({1'b0, r1} > ({1'b0, b1} + {1'b0, DIFF_TH}));
wire blue0   = (b0 > HIGH_TH) && ({1'b0, b0} > ({1'b0, r0} + {1'b0, DIFF_TH})) && ({1'b0, b0} > ({1'b0, g0} + {1'b0, DIFF_TH}));
wire blue1   = (b1 > HIGH_TH) && ({1'b0, b1} > ({1'b0, r1} + {1'b0, DIFF_TH})) && ({1'b0, b1} > ({1'b0, g1} + {1'b0, DIFF_TH}));
wire yellow0 = (r0 > HIGH_TH) && (g0 > HIGH_TH) && (b0 < LOW_TH);
wire yellow1 = (r1 > HIGH_TH) && (g1 > HIGH_TH) && (b1 < LOW_TH);
wire [1:0] white_add = {1'b0, white0} + {1'b0, white1};
wire [1:0] black_add = {1'b0, black0} + {1'b0, black1};
wire [1:0] red_add = {1'b0, red0} + {1'b0, red1};
wire [1:0] blue_add = {1'b0, blue0} + {1'b0, blue1};
wire [1:0] yellow_add = {1'b0, yellow0} + {1'b0, yellow1};

reg        vs_d;
reg        sample_en;
reg [15:0] sample_cnt;
reg [16:0] latency_cnt;
reg [15:0] white_cnt;
reg [15:0] black_cnt;
reg [15:0] red_cnt;
reg [15:0] blue_cnt;
reg [15:0] yellow_cnt;
reg [2:0]  next_color_id;
reg [4:0]  next_color_onehot;

wire frame_start = vs && !vs_d;
wire sample_done = sample_en && de && (sample_cnt >= SAMPLE_PAIRS - 1'b1);

always @(*) begin
    next_color_id = COLOR_UNKNOWN;
    next_color_onehot = 5'b00000;

    if ((white_cnt >= MIN_COLOR_COUNT) &&
        (white_cnt >= black_cnt) &&
        (white_cnt >= red_cnt) &&
        (white_cnt >= blue_cnt) &&
        (white_cnt >= yellow_cnt)) begin
        next_color_id = COLOR_WHITE;
        next_color_onehot = 5'b00001;
    end else if ((black_cnt >= MIN_COLOR_COUNT) &&
        (black_cnt >= red_cnt) &&
        (black_cnt >= blue_cnt) &&
        (black_cnt >= yellow_cnt)) begin
        next_color_id = COLOR_BLACK;
        next_color_onehot = 5'b00010;
    end else if ((red_cnt >= MIN_COLOR_COUNT) &&
        (red_cnt >= blue_cnt) &&
        (red_cnt >= yellow_cnt)) begin
        next_color_id = COLOR_RED;
        next_color_onehot = 5'b00100;
    end else if ((blue_cnt >= MIN_COLOR_COUNT) &&
        (blue_cnt >= yellow_cnt)) begin
        next_color_id = COLOR_BLUE;
        next_color_onehot = 5'b01000;
    end else if (yellow_cnt >= MIN_COLOR_COUNT) begin
        next_color_id = COLOR_YELLOW;
        next_color_onehot = 5'b10000;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vs_d <= 1'b0;
        sample_en <= 1'b0;
        sample_cnt <= 16'd0;
        latency_cnt <= 17'd0;
        white_cnt <= 16'd0;
        black_cnt <= 16'd0;
        red_cnt <= 16'd0;
        blue_cnt <= 16'd0;
        yellow_cnt <= 16'd0;
        color_id <= COLOR_UNKNOWN;
        color_onehot <= 5'b00000;
        result_valid <= 1'b0;
        latency_ok <= 1'b0;
    end else begin
        vs_d <= vs;

        if (frame_start) begin
            sample_en <= 1'b1;
            sample_cnt <= 16'd0;
            latency_cnt <= 17'd0;
            white_cnt <= 16'd0;
            black_cnt <= 16'd0;
            red_cnt <= 16'd0;
            blue_cnt <= 16'd0;
            yellow_cnt <= 16'd0;
            result_valid <= 1'b0;
            latency_ok <= 1'b0;
        end else if (sample_en) begin
            if (latency_cnt < LATENCY_LIMIT)
                latency_cnt <= latency_cnt + 1'b1;

            if (de) begin
                sample_cnt <= sample_cnt + 1'b1;
                white_cnt <= white_cnt + white_add;
                black_cnt <= black_cnt + black_add;
                red_cnt <= red_cnt + red_add;
                blue_cnt <= blue_cnt + blue_add;
                yellow_cnt <= yellow_cnt + yellow_add;

                if (sample_done) begin
                    sample_en <= 1'b0;
                    color_id <= next_color_id;
                    color_onehot <= next_color_onehot;
                    result_valid <= 1'b1;
                    latency_ok <= (latency_cnt < LATENCY_LIMIT);
                end
            end
        end
    end
end

endmodule
