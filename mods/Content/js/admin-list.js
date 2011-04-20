
function x(e){return document.getElementById(e);}
function a(e,k){return e.getAttribute(k);} 
function update_sw(elm)
{
	elm.href += '&st=' + document.body.scrollTop;
	return true;
	/*
	//alert(elm);
	var out = x('switch_img');
	var url = a(elm,'page_url');
	var newCls = elm.className == 'sw0' ? 'sw1' : 'sw0';
	var newUrl = '%%binpath%%/set_in_menus?url='+url+'&flag=' + (newCls == 'sw0' ? '0':'1');
	//alert(newCls+','+elm.className);
	out.src = newUrl + '&quiet=1';
	elm.className = newCls;
	elm.href = newUrl;
	document.body.focus();
	return false;*/
}

function _event(e)
{
	if (!e) var e = window.event;
	
	// The following 'hacks' are by 
	// Peter-Paul Koch from www.quirksmode.org
	
	// ***** Mouse Position
	var posx = 0;
	var posy = 0;
	if (e.pageX || e.pageY)
	{
		posx = e.pageX;
		posy = e.pageY;
	}
	else if (e.clientX || e.clientY)
	{
		posx = e.clientX + document.body.scrollLeft;
		posy = e.clientY + document.body.scrollTop;
	}
	e.mouse = {x:posx,y:posy};
	
	// ***** Mouse Button
	var rightclick;
	if (e.which) rightclick = (e.which == 3);
	else if (e.button) rightclick = (e.button == 2);
	e.mouse.button = { right:rightclick, left:!rightclick };
	
	
	// ***** Target of the event
	var targ;
	if (e.target) targ = e.target;
	else if (e.srcElement) targ = e.srcElement;
	if (targ.nodeType == 3) // defeat Safari bug
		targ = targ.parentNode;
	e.targ = targ;
	
	// ***** key code
	var code;
	if (e.keyCode) code = e.keyCode;
	else if (e.which) code = e.which;
	e.key = { 'code': code, str: String.fromCharCode(code) };
	
	return e;
}

function check_enter(evt,elm)
{
	if(_event(evt).key.code == 13)
		save_title(elm);
}

function save_title(elm)
{
	if(elm.getAttribute('orig_value') == elm.value)
		return;
	//alert(elm.value);		
	var out = x('switch_img');
	var pageid = elm.getAttribute('pageid');
	var url = window._binpath + '/save_title?pageid=' + pageid + '&title=' + elm.value + '&quiet=1';
	
	elm.setAttribute('orig_value', elm.value);
	
	//alert(url);
	
	var loader = x('loader' + pageid);
	if(loader)
	{
		loader.style.display = 'block';
		out.onerror = out.onload = function(){ loader.style.display = 'none'; };
	}
	
	out.src = url;
}

function check_enter2(evt,elm)
{
	if(_event(evt).key.code == 13)
		change_index(elm);
}

function change_index(elm)
{
	if(elm.getAttribute('orig_value') == elm.value)
		return;
	
	var pageid = elm.getAttribute('pageid');
	var url = window._binpath + '/change_idx?pageid=' + pageid + '&idx=' + elm.value + '&st=' + document.body.scrollTop;
	
	document.location.href = url;
}

function add_scrolltop(elm)
{
	elm.href += '&st=' + document.body.scrollTop;
}

