module fsm_tb;
    reg clk, rst, read, write, hit, memory_ready;
    reg [31:0] address;
    reg [31:0] data_from_CPU;
    
    wire SUCCESS;
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
        .SUCCESS(SUCCESS),
        .data_to_CPU(data_to_CPU)
    );
    
    //pt a aparea in waveform
    assign st = uut.st;
     
    always #10 clk = ~clk;

    //pt a a aparea in waveform si cache si dirty_bit pt ficare linie 
    wire [31:0] cache_line_0 = uut.cache_mem[0];
    wire [31:0] cache_line_1 = uut.cache_mem[1];
    wire dirty_line_0 = uut.dirty_mem[0];
    wire dirty_line_1 = uut.dirty_mem[1];
    
    //functie de afisare a starilor ca nume sa fie mai usor de urmarit
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

            $write("(dirty=%b, success=%b) ", uut.dirty_mem[uut.idx], SUCCESS);
        end
    endtask
    
    task run_fsm;

        input task_read;
        input task_write;
        input task_hit; 
        input [31:0] task_addr;
        input [31:0] task_data;
        
        //ce vine de la cache la operatia de read
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
            
            //pt a simula schimbul cache cere la ram , ram da la cache
            //while pt ca astept sa ajung in idle
            while (st != 4'b0000) begin
                if (memory_req) begin
                    #5;
                    memory_ready <= 1'b1;
                    #5;
                end
                
                //cum am scris mai sus daca e read capturae data e ce vine de la cache               
                if (SUCCESS && task_read) begin
                    captured_data = data_to_CPU;
                end

                @(posedge clk); 
                #1;  
                print_state();  
                memory_ready <= 1'b0; 
            end
           
             //afisa niste mesaje de debug ca sa ne asiguram ca totul merge ok
            if (task_read)
                $display("Citire de la adresa %h: Date trimise la CPU = %h", task_addr, captured_data);
            else if (task_write)
                $display("Scriere la adresa %h: Date salvate in Cache = %h", task_addr, task_data);

            read  <= 0;
            write <= 0;
            hit   <= 0;

            #1; 
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, fsm_tb);

        $display("-- Cache Controller 2 Lines Simulation (7 Tests) --\n");
        
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
        
     
        $display("1: citire cu HIT din Linia 0");
        run_fsm(1, 0, 1, 32'h00002000, 32'h0); 

        $display("2: citire cu MISS in Linia 0");
        run_fsm(1, 0, 0, 32'h00002000, 32'h0); 
        
        $display("3: scriere cu HIT in Linia 1");
        run_fsm(0, 1, 1, 32'h00002004, 32'hDEADBEEF); 

        $display("4: scriere cu MISS in Linia 1 (va face WRITE_BACK fiindca e dirty)");
        run_fsm(0, 1, 0, 32'hFFFF0004, 32'hCAFEAFFE); 

        $display("5: citire cu HIT din Linia 1 (verificam daca s-a pastrat valoarea)");
        run_fsm(1, 0, 1, 32'hFFFF0004, 32'h0);

        $display("6: scriere cu MISS in linia 0 (linia e curata, nu mai face WRITE_BACK!)");
        run_fsm(0, 1, 0, 32'h00005000, 32'h12345678);

        $display("7: Citire cu HIT din Linia 0");
        run_fsm(1, 0, 1, 32'h00005000, 32'h0);
        

        #100;
        $finish;
    end
endmodule