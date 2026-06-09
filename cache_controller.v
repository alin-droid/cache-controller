
module fsm(
    input clk,
    input rst,
    input read,
    input write,
    input hit,
    input memory_ready,               
    input [31:0] address,             
    input [31:0] data_from_CPU,       
    output reg memory_req,            
    output reg cpu_ready,               
    output reg [31:0] data_to_CPU     
);

    // here I define the states of the finite state machine
    // each state represents one step in the cache operation
    localparam ST_IDLE       = 4'b0000; // waits for a read or write request
    localparam ST_COMPARE    = 4'b0001; // checks if the address is already in cache
    localparam ST_READ_HIT   = 4'b0010; // successful read directly from cache
    localparam ST_READ_MISS  = 4'b0011; // read after the data has been brought into cache
    localparam ST_WRITE_HIT  = 4'b0100; // write directly into cache because there is a hit
    localparam ST_WRITE_MISS = 4'b0101; // write after the line has been brought into cache
    localparam ST_WRITE_BACK = 4'b0110; // writes back to memory if the line is dirty
    localparam ST_EVICT      = 4'b0111; // removes the old line from cache
    localparam ST_ALLOCATE   = 4'b1000; // brings a new line from memory into cache
    
    // current state and next state
    reg [3:0] st;        
    reg [3:0] st_next;   
    
    // each cache line has a dirty bit
    // dirty = 1 means that the line was modified and must be saved to memory
    reg dirty_mem [0:1];           
    
    // the cache has 2 lines, each line having 32 bits
    reg [31:0] cache_mem [0:1]; 
    
    // I use bit 2 from the address as index
    // because I only have 2 cache lines, the index can be 0 or 1
    wire idx = address[2]; 

    // here I update the FSM state and the dirty bit
    always @ (posedge clk or posedge rst) begin
        if(rst) begin
            // on reset, the FSM starts from the IDLE state
            // and the cache lines are considered clean
            st <= ST_IDLE; 
            dirty_mem[0] <= 1'b0;
            dirty_mem[1] <= 1'b0;
        end
        else begin
            // on each positive clock edge, I move to the next state
            st <= st_next;
            
            // if a write was performed, that line becomes dirty
            // meaning it was modified in cache compared to main memory
            if(st_next == ST_WRITE_HIT || st_next == ST_WRITE_MISS) 
                dirty_mem[idx] <= 1'b1;

            // after the line has been evicted, it is no longer dirty
            else if(st_next == ST_EVICT) 
                dirty_mem[idx] <= 1'b0;
        end 
    end
  
    // here is the main FSM logic
    // depending on the current state and signals, I choose the next state
    always @ (*) begin
        // by default, I remain in the same state
        st_next = st;

        case(st)

            ST_IDLE: begin
                // the FSM stays here until the CPU requests a read or write
                if(read || write) 
                    st_next = ST_COMPARE;
            end
            
            ST_COMPARE: begin
                // if we have a hit, it means the data is already in cache
                if(hit) begin 
                    if(read)       
                        st_next = ST_READ_HIT;
                    else if(write) 
                        st_next = ST_WRITE_HIT;
                end
                else begin 
                    // if we have a miss, we must check if the old line is dirty
                    // if it is dirty, it must first be written back to memory
                    if(dirty_mem[idx]) 
                        st_next = ST_WRITE_BACK;

                    // if it is not dirty, we can evict it directly
                    else               
                        st_next = ST_EVICT;
                end
            end
            
            ST_WRITE_BACK: begin
                // here we wait for memory to confirm that the write is complete
                if(memory_ready)   
                    st_next = ST_EVICT; 
                else               
                    st_next = ST_WRITE_BACK;
            end
            
            ST_EVICT: begin
                // after freeing the line, we can bring the new data
                st_next = ST_ALLOCATE;
            end
            
            ST_ALLOCATE: begin
                // here we wait for memory to send the data for the new line
                if(memory_ready) begin 
                    // after allocation, we go to read miss or write miss,
                    // depending on the initial request
                    if(read)       
                        st_next = ST_READ_MISS;
                    else if(write) 
                        st_next = ST_WRITE_MISS;
                end
                else begin
                    // if memory is not ready, we remain here
                    st_next = ST_ALLOCATE;
                end
            end
            
            // these states are final for the current operation
            // after the operation is finished, we return to IDLE
            ST_READ_HIT, ST_WRITE_HIT, ST_READ_MISS, ST_WRITE_MISS: begin
                st_next = ST_IDLE;
            end

            // if an unknown state appears, I return to IDLE as protection
            default: begin
                st_next = ST_IDLE;
            end
        endcase
    end

    // here I actually update the cache content
    always @ (posedge clk or posedge rst) begin
        if(rst) begin
            // on reset I put some initial values, just so we have something in cache
            cache_mem[0] <= 32'h11112222; 
            cache_mem[1] <= 32'h33334444; 
        end
        else begin
            // if we have write hit or write miss, I write the data from the CPU into cache
            if(st == ST_WRITE_HIT || st == ST_WRITE_MISS) begin
                cache_mem[idx] <= data_from_CPU;
            end

            // if we have allocate and memory is ready,
            // I simulate bringing a new line from memory
            else if(st == ST_ALLOCATE && memory_ready) begin
                cache_mem[idx] <= (idx == 0) ? 32'hABCDEFFF : 32'h99999999; 
            end
        end
    end

    // here I generate the FSM outputs
    always @ (*) begin
        // default values, to avoid latches
        cpu_ready = 1'b0;
        memory_req = 1'b0;
        data_to_CPU = 32'h0;

        case(st)

            // in these states I need to communicate with main memory
            // either for write-back or for bringing a new line
            ST_WRITE_BACK: begin
                memory_req = 1'b1;
            end

            ST_ALLOCATE: begin
                memory_req = 1'b1;
            end
            
            // on read, I send the value from cache to the CPU
            // and activate cpu_ready because the operation is finished
            ST_READ_HIT, ST_READ_MISS: begin
                data_to_CPU = cache_mem[idx];
                cpu_ready = 1'b1;
            end
            
            // on write, I do not need to send data to the CPU,
            // I only announce that the write is finished
            ST_WRITE_HIT, ST_WRITE_MISS: begin
                cpu_ready = 1'b1;
            end
        endcase
    end
  
endmodule

