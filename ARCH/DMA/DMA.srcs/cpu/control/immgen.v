module immgen(
   instruct,
	immediate
);
 
 
input      [31:0]  instruct ;
output reg [31:0]  immediate;
 
always@(*)
  if((instruct[6:0] == 7'b0110111) || (instruct[6:0] == 7'b0010111))     // lui/auipc
   immediate = {instruct[31:12], 12'b0};

  else
  if(instruct[6:0] == 7'b0010011)     //addi,ori,slli,srli
   immediate = { {20{instruct[31]}}, instruct[31:20] };
    
  else if(instruct[6:0] == 7'b0000011)     // All loads (lb, lh, lw, lbu, lhu)
   immediate = { {20{instruct[31]}}, instruct[31:20] };
    
  else if(instruct[6:0] == 7'b1100111)     // jalr
   immediate = { {20{instruct[31]}}, instruct[31:20] };
	
  else if(instruct[6:0] == 7'b0100011)     // All stores (sb, sh, sw)
   immediate = { {20{instruct[31]}}, instruct[31:25], instruct[11:7] };		
	
  else if(instruct[6:0] == 7'b1100011)begin                              //B-type
     if(instruct[31] == 1'b1)
       immediate = {instruct[31],19'b1,instruct[7],instruct[30:25],instruct[11:8],1'b0};	
	  else 
	    immediate = {instruct[31],19'b0,instruct[7],instruct[30:25],instruct[11:8],1'b0};  
   end	
  
  else if(instruct[6:0] == 7'b1101111)begin                              //J-type
     if(instruct[31] == 1'b1)
       immediate = {instruct[31],11'b1,instruct[19:12],instruct[20],instruct[30:21],1'b0};	
	  else 
	    immediate = {instruct[31],11'b0,instruct[19:12],instruct[20],instruct[30:21],1'b0}; 
		end		
 
  
  else 
		immediate = 32'b0;
  
	
	
endmodule