// NEUBLOCK — shared animated background
(function(){
  var canvas=document.createElement('canvas');
  canvas.id='nb-bg';
  canvas.style.cssText='position:fixed;top:0;left:0;width:100%;height:100%;z-index:0;pointer-events:none;opacity:.55;';
  document.body.prepend(canvas);
  var ctx=canvas.getContext('2d');
  var W,H,nodes=[],conns=[];
  var DARK=document.documentElement.getAttribute('data-theme')!=='light';
  function resize(){W=canvas.width=window.innerWidth;H=canvas.height=window.innerHeight;}
  resize();window.addEventListener('resize',function(){resize();init();},{passive:true});
  function mkNode(){return{x:Math.random()*W,y:Math.random()*H,vx:(Math.random()-.5)*.28,vy:(Math.random()-.5)*.28,r:Math.random()*1.6+.6,pulse:Math.random()*Math.PI*2};}
  function init(){nodes=[];for(var i=0;i<55;i++)nodes.push(mkNode());}
  init();
  var mouse={x:-9999,y:-9999};
  window.addEventListener('mousemove',function(e){mouse.x=e.clientX;mouse.y=e.clientY;},{passive:true});
  var raf;
  function draw(){
    DARK=document.documentElement.getAttribute('data-theme')!=='light';
    ctx.clearRect(0,0,W,H);
    var t=Date.now()/1000;
    nodes.forEach(function(n){
      n.x+=n.vx;n.y+=n.vy;
      if(n.x<-20)n.x=W+20;if(n.x>W+20)n.x=-20;
      if(n.y<-20)n.y=H+20;if(n.y>H+20)n.y=-20;
      var dx=mouse.x-n.x,dy=mouse.y-n.y,md=Math.sqrt(dx*dx+dy*dy);
      if(md<120){n.vx-=dx/md*.012;n.vy-=dy/md*.012;}
      n.pulse+=.018;
    });
    for(var i=0;i<nodes.length;i++){
      for(var j=i+1;j<nodes.length;j++){
        var a=nodes[i],b=nodes[j];
        var dx=a.x-b.x,dy=a.y-b.y,d=Math.sqrt(dx*dx+dy*dy);
        if(d<145){
          var alpha=(1-d/145)*.35;
          ctx.beginPath();
          ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);
          ctx.strokeStyle=DARK?'rgba(34,209,255,'+alpha+')':'rgba(2,132,199,'+alpha+')';
          ctx.lineWidth=.7;ctx.stroke();
        }
      }
    }
    nodes.forEach(function(n){
      var glow=DARK?'rgba(34,209,255,':'rgba(2,132,199,';
      var pulse=(Math.sin(n.pulse)*.4+.6);
      var g=ctx.createRadialGradient(n.x,n.y,0,n.x,n.y,n.r*3.5);
      g.addColorStop(0,glow+(pulse*.9)+')');
      g.addColorStop(1,glow+'0)');
      ctx.beginPath();ctx.arc(n.x,n.y,n.r*3.5,0,Math.PI*2);
      ctx.fillStyle=g;ctx.fill();
      ctx.beginPath();ctx.arc(n.x,n.y,n.r,0,Math.PI*2);
      ctx.fillStyle=glow+(.7*pulse)+')';ctx.fill();
    });
    raf=requestAnimationFrame(draw);
  }
  draw();
})();
