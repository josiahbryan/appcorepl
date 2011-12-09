$(document).ready(function() {
	windowsize = window.innerWidth; //Get browser size for slide overs
	//setTimeout(scrollTo, 0, 0, 1); //Hide nav bar in mobile safari

	var currentBlock = 0;   //js pointer
	var transTime    = 400; //milliseconds
	var blockHeight  = 322; //pixels
	var lastLink     = 0;   //js pointer
	
	var photoList = [
		
		{
			file:	'crop2.jpg',
			cap:	'The praise band leads a song Sunday morning'
		},
		{
			file:	'crop3.jpg',
			cap:	'Flowers and PHC'
		},
		{
			file:	'dakota-and-shawn2.jpg',
			cap:	'Dakota and Shawnasee sing during PHYSH Worship',
			offset:	{ x:0, y:-20 }
		},
		{
			file:	'hk-girls.jpg',
			cap:	'Little girls playing at HIS KROSS Sunday Evening',
			offset:	{ x:0, y:-60 }
		},
		{
			file:	'crop1.jpg',
			cap:	'Gary Zimmers leads a set of three songs Sunday'
		},
		{
			file:	'hk-boys.jpg',
			cap:	'Little boys playing on the gym HIS KROSS Sunday',
			offset:	{ x:0, y:-60 }
		},
		{
			file:	'physh-smile.jpg',
			cap:	'Ashley smiles and laughs during PHYSH Worship',
			offset:	{ x:0, y:-40 }
		},
		{
			file:	'crop4.jpg',
			cap:	'PHC and freshly-cut grass'
		}
	];
	var currentPhotoNum = 0;
	var photoBasePath = "%%modpath%%/images/photos/";
	
	var lastPhotoNavItem;
	function showPhoto(idx)
	{
		if(lastPhotoNavItem)
			lastPhotoNavItem.removeClass("current");
		lastPhotoNavItem = $("#photo-nav-"+idx).addClass("current");
		
		currentPhotoNum = idx;
		var data = photoList[idx];
		var nextPhoto = photoBasePath+data.file;
		var holder = $("#photo-holder");
		holder.attr("src",nextPhoto);
		
		if(data.offset)
		{
			holder.css("margin-top",data.offset.y+"px");
			holder.css("margin-left",data.offset.x+"px");
		}
		else
		{
			holder.css("margin","0px");
		}
		
		if(data.cap)
		{
			$("#photo-cap-wrap").show();
			$("#photo-cap").html(data.cap);
		}
		else
		{
			$("#photo-cap-wrap").hide();
		}
		
	}
	
	function showNextPhoto()
	{
		currentPhotoNum ++;
		if(currentPhotoNum >= photoList.length)
			currentPhotoNum = 0;
			
		showPhoto(currentPhotoNum);
	}
	
	var currentSuffix;
	function showBlock(blockSuffix)
	{
		var newBlockId = 'block-'+blockSuffix;
		var newLinkId  = 'link-' +blockSuffix;
		
		if(currentSuffix == blockSuffix)
		{
			if(blockSuffix == 'photos')
				showNextPhoto();
			return;
		}
		
		currentSuffix = blockSuffix;
			
		if(currentBlock)
		{
			// animate the hiding of the currently visible block
			currentBlock.animate({top: '-' + blockHeight}, transTime,
				function() {
					// after anim, put the block back down below the viewport
					var th = $(this);
					th.animate({top:blockHeight},0);
					th.hide();
					
					if(th.attr("id") == "block-photos")
					{
						showNextPhoto();
						//alert("next photo: "+nextPhoto);
					}
				}
			);
		}
		
		// animate the requested block
		currentBlock = $('#'+newBlockId);
		currentBlock.show();
		currentBlock.animate({top:0}, transTime);
		
		// update link styles
		if(lastLink)
			lastLink.removeClass('current');
		
		var linkElm = $('#'+newLinkId);
		if(linkElm)
		{
			linkElm.addClass('current');
			lastLink = linkElm;
		}
	}
	
	// list of block suffixes to rotate through
	var blockList     = ['photos','video','events','talk'];
	var blockIdx      = -1;     // current index into blockList 
	var blockShowTime = 10000;   // length of time to show each block
	var userOverride  = false;  // if true, dont auto change blocks
	var blockPRogress = 0;
	
	
	// IE doesn't like our CSS 'overflow' prop on the Talk block, so it doesn't
	// render anything in this area. Therefore, remove the 'talk' item from the
	// end of the list of blocks to show when auto rotating. The user can still
	// click on the link and code below allows the link to fall thru if IE
	// for the talk block.
	if($.browser.msie)
		blockList.length --; 
		
	
	function getTimestamp()
	{
		var time = new Date();
		return (time.getMinutes() * 60 * 1000) + (time.getSeconds() * 1000) + time.getMilliseconds();
	}
	
	function updateBlockProgress()
	{
		var time = (getTimestamp() - blockProgress) / blockShowTime; 
		if(time < 1)
		{
			var w = time * 50;
			var nbr = parseInt((1-time) * (blockShowTime/1000) +1);
			$("#block-timer").width(w);
			$("#block-time-nbr").html(nbr);
			setTimeout(updateBlockProgress, 1000/2); 
		}
	}
	
	if(document.location.hash)
	{
		var h = document.location.hash + "";
		h = h.substring(1,h.length);
		//alert(h);
		var idx=-1;
		for(i=0;i<blockList.length;i++)
		{
			if(h == blockList[i])
				idx = i;
		}
		
		//alert(idx);
		//alert(h);
		if(idx > -1)
		{
			blockIdx = idx-1; // -1 for when the first call to showNextBlock() happens in 100 ms...
			showBlock(h);
		}
	}
	
	function showNextBlock()
	{
		if(userOverride)
			return;
		
		// get next block#
		blockIdx ++;
		if(blockIdx >= blockList.length)
			blockIdx = 0;
			
		// show the block
		var blockSuffix = blockList[blockIdx];
		showBlock(blockSuffix);
		
		// set timer to change blocks
		setTimeout(showNextBlock, blockShowTime);
		
		blockProgress = getTimestamp();
		setTimeout(updateBlockProgress, 1000/2);
	}
	
	
	
	
	// start the rotator
	setTimeout(showNextBlock, 100);
	
	function userOverrideBlock()
	{
		userOverride = true;
		$("#block-timer").hide();
		$("#block-time-nbr").hide();
	}
	
	$('#sidebar .sidebar-link-block .link-block').live("click", function() {
	
		var suffix = $(this).attr('block-suffix');
		if(!suffix)
		{
			suffix = $(this).attr('href');
			suffix = suffix.substr(1,suffix.length());
		}
		
		// IE doesn't like our CSS 'overflow' prop on the Talk block, so it doesn't
		// render anything in this area. Therefore, just fall thru with the link
		// click and allow browser to redirect.
		if($.browser.msie && suffix == 'talk')
			return true; 
		
		
		showBlock(suffix);
		
		userOverrideBlock();
		
		return false;
	});
	
	function setupPhotoNav()
	{
		var holder = $("#photo-nav");
		for(var i=0;i<photoList.length;i++)
		{
			var data = photoList[i];
			var html = "<a href='#' class='photo-nav-link' idx='"+i+"' id='photo-nav-"+i+"'>"+(i+1)+"</a>";
			//console.debug(html);
			var link = $(html);
			link.attr("title",data.cap);
			link.attr("href", photoBasePath + data.file);
			link.appendTo(holder);
		}
		
		// Already displayed when page loaded...
		lastPhotoNavItem = $("#photo-nav-0").addClass('current');
		
		$(".photo-nav-link").live('click',function(){
			var idx = $(this).attr("idx");
			showPhoto(parseInt(idx));
			userOverrideBlock();     // prevent blocks from changing
			return false;
		});
	}
	
	setupPhotoNav();
	
	//alert(document.location.hash);
	
// 	$("#header .logo a").live("click", function() { // Main Navigation
// 		var url = $(this).attr('href');
// 		$(this).ajaxSend(function() {
// 			$('#loading-box').show();
// 		});
// 		$(this).ajaxSuccess(function() {
// 			$('#loading-box').hide();
// 			$(this).unbind("ajaxSend");
// 		});
// 		$('#site-container').load(url);
// 		return false;
// 	});
// 	
// 	$("#nav ul li a").live("click", function() { // Main Navigation
// 		var url = $(this).attr('href');
// 		$(this).ajaxSend(function() {
// 			$('#loading-box').show();
// 		});
// 		$(this).ajaxSuccess(function() {
// 			$('#loading-box').hide();
// 			$(this).unbind("ajaxSend");
// 		});
// 		$('#site-container').load(url);
// 		return false;
// 	});
// 	
// 	$('.content .other-link').live("click", function() { // Ajax link to contact forms
// 		var url = $(this).attr('href');
// 		$('#selected-item .content').load(url, function() {
// 			$('#selected-item').show();
// 			$.scrollTo(0,0);
// 			$('#main-page').animate({left: '-'+windowsize},400);
// 		});
// 		return false;
// 	});	
});