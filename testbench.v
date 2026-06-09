
module fsm_tb;
    reg clk, rst, read, write, hit, memory_ready;
    reg [31:0] address;
    reg [31:0] data_from_CPU;
    
    wire cpu_ready;
    wire [31:0] data_to_CPU;
    wire memory_req;
    wire [3:0] st; 
     
    fsm uut (
        .clk(clk),
        .rst(rst),
        .read(read),
        .write(write),
        .hit(hit),
        .memory_ready(memory_ready),
        .address(address),
        .data_from_CPU(data_from_CPU),
        .memory_req(memory_req),
        .cpu_ready(cpu_ready),
        .data_to_CPU(data_to_CPU)
    );
    
    // used to make the current state visible in the waveform
    assign st = uut.st;
     
    always #10 clk = ~clk;

    // used to make the cache lines and dirty bits visible in the waveform
    wire [31:0] cache_line_0 = uut.cache_mem[0];
    wire [31:0] cache_line_1 = uut.cache_mem[1];
    wire dirty_line_0 = uut.dirty_mem[0];
    wire dirty_line_1 = uut.dirty_mem[1];
    
    // task used to display the state names, making the simulation easier to follow
    task print_state;
        begin 
            case(st) 
                4'b0000: $write("IDLE");
                4'b0001: $write("COMPARE");
                4'b0010: $write("READ_HIT");
                4'b0011: $write("READ_MISS");
                4'b0100: $write("WRITE_HIT");
                4'b0101: $write("WRITE_MISS");
                4'b0110: $write("WRITE_BACK");
                4'b0111: $write("EVICT");
                4'b1000: $write("ALLOCATE");
                default: $write("UNKNOWN");
            endcase

            $write("(dirty=%b, cpu_ready=%b) ", uut.dirty_mem[uut.idx], cpu_ready);
        end
    endtask
    
    task run_fsm;

        input task_read;
        input task_write;
        input task_hit; 
        input [31:0] task_addr;
        input [31:0] task_data;
        
        // stores the data returned by the cache during a read operation
        reg [31:0] captured_data;

        begin
            read          <= task_read;
            write         <= task_write;
            hit           <= task_hit;
            address       <= task_addr;
            data_from_CPU <= task_data;
            memory_ready  <= 1'b0;
           
            @(posedge clk);
            #1;
            print_state(); 
            
            // simulates the exchange between cache and RAM:
            // the cache sends a memory request, and RAM responds when ready
            // the while loop is used because we wait until the FSM returns to IDLE
            while (st != 4'b0000) begin
                if (memory_req) begin
                    #5;
                    memory_ready <= 1'b1;
                    #5;
                end
                
                // if the operation is a read, capture the data sent from cache to CPU              
                if (cpu_ready && task_read) begin
                    captured_data = data_to_CPU;
                end

                @(posedge clk); 
                #1;  
                print_state();  
                memory_ready <= 1'b0; 
            end
           
            // prints debug messages to check that everything works correctly
            if (task_read)
                $display("read at address %h: data to CPU = %h", task_addr, captured_data);
            else if (task_write)
                $display("write at adress %h: data saved in cache = %h", task_addr, task_data);

            read  <= 0;
            write <= 0;
            hit   <= 0;

            #1; 
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, fsm_tb);
        
        clk = 0;
        rst = 0;
        read = 0;
        write = 0;
        hit = 0;
        memory_ready = 0;
        address = 0;
        data_from_CPU = 0;
         
        #5  rst = 1;
        #20 rst = 0;
        #5; 
        
     
        $display("line 0 read hit");
        run_fsm(1, 0, 1, 32'h00002000, 32'h0); 

        $display("line 0 read miss");
        run_fsm(1, 0, 0, 32'h00002000, 32'h0); 
        
        $display("line 1 write hit 3");
        run_fsm(0, 1, 1, 32'h00002004, 32'hDEADBEEF); 

        $display("line 1 write miss 4: (write back , dirty=1) ");
        run_fsm(0, 1, 0, 32'hFFFF0004, 32'hCAFEAFFE); 

        $display("line 1 read hit (to see if the value is modified)");
        run_fsm(1, 0, 1, 32'hFFFF0004, 32'h0);

        $display("line 0 write miss (no need for write back)");
        run_fsm(0, 1, 0, 32'h00005000, 32'h12345678);

        $display("line 0 read hit");
        run_fsm(1, 0, 1, 32'h00005000, 32'h0);
        

        #100;
        $finish;
    end
endmodule
