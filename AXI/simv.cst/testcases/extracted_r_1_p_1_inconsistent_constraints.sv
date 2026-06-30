class c_1_1;
    rand bit[31:0] awaddr; // rand_mode = ON 

    constraint addr_map_c_this    // (constraint_mode = ON) (tb/axi_pkg.sv:128)
    {
       ((awaddr[31:28]) inside {4'h0, 4'h1});
    }
    constraint WITH_CONSTRAINT_this    // (constraint_mode = ON) (tb/sequence_lib.sv:204)
    {
       ((awaddr[31:28]) == 4'hf);
    }
endclass

program p_1_1;
    c_1_1 obj;
    string randState;

    initial
        begin
            obj = new;
            randState = "111101xz10111zzxz1101xxz01xzzzxxxxxzzxzzxxxxxzxxxzzxxzzzxzxzxzxx";
            obj.set_randstate(randState);
            obj.randomize();
        end
endprogram
