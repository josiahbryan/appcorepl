$(function()
{
	setTimeout(function()
	{
		if(window.USER_DISPLAY == 'Josiah Bryan' ||
		   window.USER_DISPLAY == 'Bruce Bryan')
		{
			// probably testing - dont post! :-)
			return;
		}
		var name = window.USER_DISPLAY ? window.USER_DISPLAY : prompt("Welcome! Would you be willing to share your name with us? You can also just click 'Cancel' to remain anonymous. Thanks for watching!");
		if(name)
		{
			var postData = {
				comment: name+" is watching the live stream!",
				poster_name: "Live Stream Page",
				poster_email: "",
				output_fmt: "json",
				plain_text: 1
			};
			
			
			if(!window.USER_DISPLAY)
			{
				var elm = $('#newpost_poster_name').get(0);
				if(elm)
					elm.value = name;
			}
			
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
	}, 1000); // allow the window.USER_DISPLAY value to get set...
});
