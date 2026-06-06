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

    // aici definesc starile automatului
    // fiecare stare reprezinta un pas din functionarea cache-ului
    localparam ST_IDLE       = 4'b0000; // asteapta o cerere de read sau write
    localparam ST_COMPARE    = 4'b0001; // verifica daca adresa se afla deja in cache
    localparam ST_READ_HIT   = 4'b0010; // citire reusita direct din cache
    localparam ST_READ_MISS  = 4'b0011; // citire dupa ce datele au fost aduse in cache
    localparam ST_WRITE_HIT  = 4'b0100; // scriere direct in cache, pentru ca exista hit
    localparam ST_WRITE_MISS = 4'b0101; // scriere dupa ce linia a fost adusa in cache
    localparam ST_WRITE_BACK = 4'b0110; // scrie inapoi in memorie daca linia este dirty
    localparam ST_EVICT      = 4'b0111; // elimina linia veche din cache
    localparam ST_ALLOCATE   = 4'b1000; // aduce o linie noua din memorie in cache
    
    // starea curenta si starea urmatoare
    reg [3:0] st;        
    reg [3:0] st_next;   
    
    // fiecare linie din cache are cate un dirty bit
    // dirty = 1 inseamna ca linia a fost modificata si trebuie salvata in memorie
    reg dirty_mem [0:1];           
    
    // cache-ul are 2 linii, fiecare linie avand 32 de biti
    reg [31:0] cache_mem [0:1]; 
    
    // folosesc bitul 2 din adresa ca index
    // pentru ca am doar 2 linii de cache, indexul poate fi 0 sau 1
    wire idx = address[2]; 

    // aici actualizez starea automatului si dirty bit-ul
    always @ (posedge clk or posedge rst) begin
        if(rst) begin
            // la reset, automatul porneste din starea IDLE
            // si liniile din cache sunt considerate curate
            st <= ST_IDLE; 
            dirty_mem[0] <= 1'b0;
            dirty_mem[1] <= 1'b0;
        end
        else begin
            // la fiecare front pozitiv de ceas trec in starea urmatoare
            st <= st_next;
            
            // daca am facut o scriere, linia respectiva devine dirty
            // adica s-a modificat in cache fata de memoria principala
            if(st_next == ST_WRITE_HIT || st_next == ST_WRITE_MISS) 
                dirty_mem[idx] <= 1'b1;

            // dupa ce linia a fost evacuata, nu mai este dirty
            else if(st_next == ST_EVICT) 
                dirty_mem[idx] <= 1'b0;
        end 
    end
  
    // aici este logica principala a automatului
    // in functie de starea curenta si de semnale, aleg starea urmatoare
    always @ (*) begin
        // implicit raman in aceeasi stare
        st_next = st;

        case(st)

            ST_IDLE: begin
                // automatul sta aici pana cand CPU-ul cere read sau write
                if(read || write) 
                    st_next = ST_COMPARE;
            end
            
            ST_COMPARE: begin
                // daca avem hit, inseamna ca datele sunt deja in cache
                if(hit) begin 
                    if(read)       
                        st_next = ST_READ_HIT;
                    else if(write) 
                        st_next = ST_WRITE_HIT;
                end
                else begin 
                    // daca avem miss, trebuie sa vedem daca linia veche e dirty
                    // daca e dirty, trebuie intai scrisa inapoi in memorie
                    if(dirty_mem[idx]) 
                        st_next = ST_WRITE_BACK;

                    // daca nu e dirty, o putem elimina direct
                    else               
                        st_next = ST_EVICT;
                end
            end
            
            ST_WRITE_BACK: begin
                // aici asteptam memoria sa confirme ca a terminat scrierea
                if(memory_ready)   
                    st_next = ST_EVICT; 
                else               
                    st_next = ST_WRITE_BACK;
            end
            
            ST_EVICT: begin
                // dupa ce am eliberat linia, putem aduce datele noi
                st_next = ST_ALLOCATE;
            end
            
            ST_ALLOCATE: begin
                // aici asteptam ca memoria sa trimita datele pentru linia noua
                if(memory_ready) begin 
                    // dupa alocare, mergem spre read miss sau write miss,
                    // in functie de cererea initiala
                    if(read)       
                        st_next = ST_READ_MISS;
                    else if(write) 
                        st_next = ST_WRITE_MISS;
                end
                else begin
                    // daca memoria nu e gata, ramanem aici
                    st_next = ST_ALLOCATE;
                end
            end
            
            // starile acestea sunt finale pentru operatia curenta
            // dupa ce operatia s-a terminat, revenim in IDLE
            ST_READ_HIT, ST_WRITE_HIT, ST_READ_MISS, ST_WRITE_MISS: begin
                st_next = ST_IDLE;
            end

            // daca apare o stare necunoscuta, revin in IDLE ca protectie
            default: begin
                st_next = ST_IDLE;
            end
        endcase
    end

    // aici actualizez efectiv continutul cache-ului
    always @ (posedge clk or posedge rst) begin
        if(rst) begin
            // la reset pun niste valori initiale, doar ca sa avem ceva in cache
            cache_mem[0] <= 32'h11112222; 
            cache_mem[1] <= 32'h33334444; 
        end
        else begin
            // daca am write hit sau write miss, scriu in cache datele venite de la CPU
            if(st == ST_WRITE_HIT || st == ST_WRITE_MISS) begin
                cache_mem[idx] <= data_from_CPU;
            end

            // daca am allocate si memoria este gata,
            // simulez aducerea unei linii noi din memorie
            else if(st == ST_ALLOCATE && memory_ready) begin
                cache_mem[idx] <= (idx == 0) ? 32'hABCDEFFF : 32'h99999999; 
            end
        end
    end

    // aici generez iesirile automatului
    always @ (*) begin
        // valori implicite, ca sa evit latch-uri
        SUCCESS = 1'b0;
        memory_req = 1'b0;
        data_to_CPU = 32'h0;

        case(st)

            // in starile acestea am nevoie sa comunic cu memoria principala
            // fie pentru write-back, fie pentru aducerea unei linii noi
            ST_WRITE_BACK: begin
                memory_req = 1'b1;
            end

            ST_ALLOCATE: begin
                memory_req = 1'b1;
            end
            
            // la citire, trimit catre CPU valoarea din cache
            // si activez SUCCESS ca operatia s-a terminat
            ST_READ_HIT, ST_READ_MISS: begin
                data_to_CPU = cache_mem[idx];
                SUCCESS = 1'b1;
            end
            
            // la scriere nu trebuie sa trimit date catre CPU,
            // doar anunt ca scrierea s-a terminat
            ST_WRITE_HIT, ST_WRITE_MISS: begin
                SUCCESS = 1'b1;
            end
        endcase
    end
  
endmodule