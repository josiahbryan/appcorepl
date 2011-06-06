$(function()
{
	var name = prompt("Welcome! Would you be willing to share your name with us? You can also just click 'Cancel' to remain anonymous. Thanks for watching!");
	if(name)
	{
		var postData = {
			comment: name+" is watching the live stream!",
			poster_name: "Live Stream Page",
			poster_email: "",
			output_fmt: "json",
			plain_text: 1
		};
		
		
		
		var postUrl = "/about/website/post";
		//alert(postUrl);
		$.ajax({
			type: "POST",
			url: postUrl,
			data: postData,
			success: function(data)
			{

			}
		});
	}

});
