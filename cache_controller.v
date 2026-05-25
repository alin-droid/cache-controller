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
    output reg SUCCESS,               
    output reg [31:0] data_to_CPU     
);

    localparam ST_IDLE       = 4'b0000; 
    localparam ST_COMPARE    = 4'b0001; 
    localparam ST_READ_HIT   = 4'b0010; 
    localparam ST_READ_MISS  = 4'b0011; 
    localparam ST_WRITE_HIT  = 4'b0100; 
    localparam ST_WRITE_MISS = 4'b0101; 
    localparam ST_WRITE_BACK = 4'b0110; 
    localparam ST_EVICT      = 4'b0111; 
    localparam ST_ALLOCATE   = 4'b1000;  
    
    reg [3:0] st;        
    reg [3:0] st_next;   
    
    //fiecare linie are un dirty bit
    reg dirty_mem [0:1];           
    
    //avem 2 linii de memorie cache
    reg [31:0] cache_mem [0:1]; 
    
    //folosesc primul bit dup? offset ca s? aleg între cele 2 linii de cache.
    wire idx = address[2]; 

    //calcul dirty_bit
    always @ (posedge clk or posedge rst) begin
        if(rst) begin
            st <= ST_IDLE; 
            dirty_mem[0] <= 1'b0;
            dirty_mem[1] <= 1'b0;
        end
        else begin
            st <= st_next;
            
            if(st_next == ST_WRITE_HIT || st_next == ST_WRITE_MISS) 
                dirty_mem[idx] <= 1'b1;
            else if(st_next == ST_EVICT) 
                dirty_mem[idx] <= 1'b0;
        end 
    end
  
    //logica de fsm
    always @ (*) begin
        st_next = st;
        case(st)
            ST_IDLE: begin
                if(read || write) 
                    st_next = ST_COMPARE;
            end
            
            ST_COMPARE: begin
                if(hit) begin 
                    if(read)       st_next = ST_READ_HIT;
                    else if(write) st_next = ST_WRITE_HIT;
                end
                else begin // MISS
                    if(dirty_mem[idx]) st_next = ST_WRITE_BACK; // verifica doar bitul liniei curente
                    else               st_next = ST_EVICT;
                end
            end
            
            ST_WRITE_BACK: begin
                if(memory_ready)   st_next = ST_EVICT; 
                else               st_next = ST_WRITE_BACK;
            end
            
            ST_EVICT: begin
                st_next = ST_ALLOCATE;
            end
            
            ST_ALLOCATE: begin
                if(memory_ready) begin 
                    if(read)       st_next = ST_READ_MISS;
                    else if(write) st_next = ST_WRITE_MISS;
                end
                else begin
                    st_next = ST_ALLOCATE;
                end
            end
            
            ST_READ_HIT, ST_WRITE_HIT, ST_READ_MISS, ST_WRITE_MISS: st_next = ST_IDLE;
            default: st_next = ST_IDLE;
        endcase
    end

    // actualizarea memoriei cache
    always @ (posedge clk or posedge rst) begin
        if(rst) begin
            //faloru random
            cache_mem[0] <= 32'h11112222; 
            cache_mem[1] <= 32'h33334444; 
        end
        else begin
            if(st == ST_WRITE_HIT || st == ST_WRITE_MISS) begin
                cache_mem[idx] <= data_from_CPU;
            end
            else if(st == ST_ALLOCATE && memory_ready) begin
                //la fel alocam valori random
                cache_mem[idx] <= (idx == 0) ? 32'hABCDEFFF : 32'h99999999; 
            end
        end
    end

    // logica pt iesiri
    always @ (*) begin
        SUCCESS = 1'b0;
        memory_req = 1'b0;
        data_to_CPU = 32'h0;

        case(st)
            ST_WRITE_BACK: memory_req = 1'b1;
            ST_ALLOCATE:   memory_req = 1'b1;
            
            ST_READ_HIT, ST_READ_MISS: begin
                data_to_CPU = cache_mem[idx];
                SUCCESS = 1'b1;
            end
            
            ST_WRITE_HIT, ST_WRITE_MISS: begin
                SUCCESS = 1'b1;
            end
        endcase
    end
  
endmodule