	$(".postlist a.readmore_link").live("click",function() {
		
		var	th     = $(this),
			postid = th.attr('postid');
			state  = th.attr('state');
		
		if(state == 'loaded')
		{
			var	shortId = "#short_text_"+postid,
				blockId = "#long_text_"+postid,
				rowRef = $("tr.#post"+postid),
				off = rowRef.offset();
			
			// Probably a "comment" read more link, not a post readmore link, 
			// so find the comment wrapper <div> offset
			if(!off)
				off = (rowRef = $("#wrap"+postid)).offset();
			
			$(shortId).show(300);
			$(blockId).hide(300);
			// only scroll doc if top of the post is above the window top.
			// That way we dont "confuse" the user with unnecessary changes
			if(off && off.top < document.body.scrollTop)
				$.scrollTo(rowRef,300);
				
			th.attr('state', 'unloaded');
			th.html('Read More &raquo;');
			
		}
		else
		{
			th.attr('state', 'loaded');
			th.html('&laquo; Less');
			
			var	blockId  = "#long_text_"+postid,
				shortId  = "#short_text_"+postid,
				postHref = th.attr('href'),
				loading  = $('<img/>')
					.attr('src',loaderGif)
					.attr('align','absmiddle');
				
			$("body").css("cursor", "progress");
			th.css("cursor", "progress");
			
			loading.insertAfter(th);
			
			var errorFunc = function() 
			{
				// Error loading, just redirect to the page itself...
				document.location.href = postHref; 
			};
			
			$.ajax({
				type: "GET",
				url: postHref,
				data:
				{
					output_fmt: "json",
					no_comments: 1
				},
				success: function(data)
				{
					//alert("Got post data:"+data+", type:"+typeof(data));
					if(typeof(data) == "string")
					{
						// something wierd on server - should be JSON!
						errorFunc();
					}
					else
					{
						$(blockId).html(data.post_text);
						$(shortId).hide();
						$(blockId).show(300);
						loading.remove();
						
						// Remove busy cursor
						$("body").css("cursor", "auto");
						th.css("cursor", "pointer");
						
						//alert(data);
						//console.debug(data);
					}	
				},
				error: errorFunc
				
			});
		}
		
		return false;
	});
	
	$(".postlist .actions .add_like a").live("click",function(){
		//alert("Not done yet");
		
		var th = $(this),
		    // Create a loading indicator
		    loading = $('<img/>')
		    	.attr('src',loaderGif)
		    	.attr('align','absmiddle')
		    	.attr('class','like-loading-img');
		
		loading.insertAfter(th);
		
		var postid = th.attr('postid');
		
		var postUrl = th.attr('like_url');
		//alert(postUrl);
		$.ajax({
			type: "POST",
			url: postUrl,
			//data: postData,
			success: function(data)
			{
				//console.debug("got post data: "+data+", typeof: "+typeof(data));
				//alert("Got post data:"+data+", type:"+typeof(data));
				loading.remove();
				
				$("#addlike"+postid).hide();
				$("#youlike"+postid).show();
				$("#unlike" +postid).show();
			}
		});
				
		
		return false;
	});
	
	$(".postlist .actions .unlike a").live("click",function(){
		//alert("Not done yet");
		
		var th = $(this),
		    // Create a loading indicator
		    loading = $('<img/>')
		    	.attr('src',loaderGif)
		    	.attr('align','absmiddle')
		    	.attr('class','like-loading-img');
		
		loading.insertAfter(th);
		
		var postid = th.attr('postid');
		
		var postUrl = th.attr('unlike_url');
		//alert(postUrl);
		$.ajax({
			type: "POST",
			url: postUrl,
			//data: postData,
			success: function(data)
			{
				//console.debug("got post data: "+data+", typeof: "+typeof(data));
				//alert("Got post data:"+data+", type:"+typeof(data));
				loading.remove();
				
				$("#addlike"+postid).show();
				$("#youlike"+postid).hide();
				$("#unlike" +postid).hide();
			}
		});
		
		
		return false;
	});
	
	$(".postlist .comment_text .delete_comment_link").live("click",function(){
		
		if(!confirm("Are you sure you want to delete this?"))
			return false;
			
			
		var th = $(this),
		    // Create a loading indicator
		    loading = $('<img/>')
		    	.attr('src',loaderGif)
		    	.attr('align','absmiddle')
		    	.attr('class','like-loading-img');
		
		loading.insertAfter(th);
		
		var postid = th.attr('postid');
		
		var postUrl = th.attr('href');
		//alert(postUrl);
		$.ajax({
			type: "POST",
			url: postUrl,
			success: function(data)
			{
				loading.remove();
				
				var ref = $("#wrap"+postid);
				ref.hide(300, function() { ref.remove() });
			}
		});
	
		return false;
	});
	
	
	$(".postlist tr.post .delete_post_link").live("click",function(){
		
		if(!confirm("Are you sure you want to delete this?"))
			return false;
			
		var th = $(this),
		    // Create a loading indicator
		    loading = $('<img/>')
		    	.attr('src',loaderGif)
		    	.attr('align','absmiddle')
		    	.attr('class','like-loading-img');
		
		loading.insertAfter(th);
		
		var postid = th.attr('postid');
		
		var postUrl = th.attr('href');
		//alert(postUrl);
		$.ajax({
			type: "POST",
			url: postUrl,
			success: function(data)
			{
				loading.remove();
				
				var ref = $("#post"+postid); 
				ref.hide(300, function() { ref.remove() });
			}
		});
	
		return false;
	});
	