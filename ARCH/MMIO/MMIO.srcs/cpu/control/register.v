module register(
	input		clk,
	input 		rst_n,
	input 		regwrite,   
	input[4:0]	 write_register,
	input[31:0]	write_data, 
	input [4:0]	read_register1, 
	output  [31:0] read_data1,
	input[4:0]	read_register2, 
	output  [31:0]  read_data2
);
	reg[31:0]  register[0:31]; 
 
	always @ (negedge clk or negedge rst_n) begin
	  if(!rst_n) begin:reset_all_registers
	    integer i;
		for(i=0;i<32;i=i+1)
	    register[i] <= 32'd0;
	   end
	  else begin
		if((regwrite == 1'b1) && (write_register != 5'h0)) begin
		  register[write_register] <= write_data;
		 end
	  end
	end
 assign read_data1 = (read_register1 == 5'd0) ? 32'd0 : register[read_register1]; 
 assign read_data2 = (read_register2 == 5'd0) ? 32'd0 : register[read_register2];
endmodule