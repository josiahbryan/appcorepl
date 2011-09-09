	function isImageOk(img) {
		// During the onload event, IE correctly identifies any images
		// that weren't downloaded as not complete. Others should too.
		// Gecko-based browsers act like NS4 in that they report this
		// incorrectly: they always return true.
		if (!img.complete) {
			return false;
		}
		
		// However, they do have two very useful properties: naturalWidth
		// and naturalHeight. These give the true size of the image. If
		// it failed to load, either of these should be zero.
		if (typeof img.naturalWidth != "undefined" && img.naturalWidth == 0) {
			return false;
		}
		
		// No other way of checking: assume it's ok.
		return true;
	}
		
	// Scale images that are below posts (e.g. automatically added based on links in text) to below 100x...  
	function scaleImages() 
	{ 
		$(".image-link img").each(function(){
			var t = this,
			th = $(t);
	
			t.onload = function()
			{
				var w  = parseFloat(th.width()),
				h  = parseFloat(th.height()),
				ar = h/w,
				newWidth  = 320.0, 
				newHeight = newWidth * ar;
				
				if(w > newWidth || h > newHeight)
				{
					th.css("width",  newWidth +"px");
					th.css("height", newHeight+"px");
					
				}
			};
			
			if(isImageOk(t))
				t.onload();
		});
	}
	scaleImages();
	
	function runOnloadScripts()
	{
		var list = window.VideoProviderList;
		for(var i=0;i<list.length;i++)
		{
			if(list[i].extra_js)
			{
				eval(list[i].extra_js);
			}
		}
		
		scaleImages();
		
		if(window.RunOnloadPosts)
		{
			var list = window.RunOnloadPosts;
			for(var i=0;i<list.length;i++)
			{
				var func = list[i];
				if(typeof(func) == 'function')
				{
					func();
				}
			}
		}
	}
	
	var loadingIndicator = 0;
	$(function(){ 
		loadingIndicator = $('<img/>')
			.attr('src',window.loaderGif)
			.attr('align','absmiddle')
			.attr('class','like-loading-img');
	});
	function getLoadingIndicator(/*ctx*/)
	{
		return loadingIndicator;
	}
	
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
				loading  = getLoadingIndicator("like");
				
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
						
						runOnloadScripts();
						
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
		    loading = getLoadingIndicator("like");
		
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
		    loading = getLoadingIndicator("like");
		
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
		    loading = getLoadingIndicator("delete");
		
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
		    loading = getLoadingIndicator("like");
		
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
	
