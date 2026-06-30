class c_2_2;
    rand bit[31:0] araddr; // rand_mode = ON 

    constraint addr_map_c_this    // (constraint_mode = ON) (tb/axi_pkg.sv:128)
    {
       ((araddr[31:28]) inside {4'h0, 4'h1});
    }
    constraint WITH_CONSTRAINT_this    // (constraint_mode = ON) (tb/sequence_lib.sv:214)
    {
       ((araddr[31:28]) == 4'hf);
    }
endclass

program p_2_2;
    c_2_2 obj;
    string randState;

    initial
        begin
            obj = new;
            randState = "1z000xxz0x0x1zzxxx101x11x01x1xxxxxxxxzzzxzzxzzzzxzxzxxzzzxxxxzzz";
            obj.set_randstate(randState);
            obj.randomize();
        end
endprogram
