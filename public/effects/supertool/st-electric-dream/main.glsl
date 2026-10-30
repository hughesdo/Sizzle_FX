// Imported from SuperTool effects/ElectricDream.glsl by scripts/import-supertool.mjs
// Electric Dream
// Source: OneOffRender Shaders/ElectricDream.glsl (upstream: https://www.shadertoy.com/view/ld23Wd).
//
// SuperTool intake note: stripped #version, removed OneOffRender Y-flip
// boilerplate (gl_FragCoord is already upright in WebGL2).
// Audio reads remapped iChannel0 → iAudioFFT with Shadertoy↔SuperTool row
// swap (FFT row 0 → 0.75, PCM row 1 → 0.25). Visual logic preserved.

// Original author: mu6k
// Modified by: ArthurTent for ShaderAmp project
// URL: https://www.shadertoy.com/view/ld23Wd
// License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License
// Converted to OneOffRender format

// Audio texture
// uniform sampler2D iChannel0;  // Video texture (disabled - OneOffRender doesn't support video textures yet)


// https://www.shadertoy.com/view/ld23Wd
// Modified by ArthurTent
// Created by mu6k
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License
// https://creativecommons.org/licenses/by-nc-sa/3.0/

#define VIDEO

/*by mu6k, Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
	
2016-02-02:

	Bugfix, and set a tune from soundcloud to which it reacts better :)


2014-03-21:

	An audio visualizer I've been working on... enjoy!!!!

*/

#define s(x) smoothstep(0.15, 0.3, x * 1.1 - 0.1)
vec3 chromaKey(vec3 x, vec3 y){
	vec2 c = s(vec2(x.g - x.r * x.y, x.g));

    return mix(x, y, c.x * c.y);
}
vec3 getTexture(vec2 p){
	vec4 tex = texture(iChannel0, p);
    return tex.xyz * tex.w;
}
void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
	vec2 tuv = fragCoord.xy / iResolution.xy;
	vec2 uv = fragCoord.xy / iResolution.yy-vec2(.9,.5);
	
	float acc = .0;
	float best = .0;
	float best_acc = .0;
	
	for (float i = .0; i<0.5; i+=.008)
	{
		acc+=texture(iAudioFFT, vec2(i, 0.25)).x-.5;
		if (acc>best_acc)
		{
			best_acc = acc;
			best = i;
		}
	}
	
	vec3 colorize = vec3(.2);
	
	for (float i = .0; i< 1.0; i+=.05)
	{
		colorize[int(i*3.0)]+=texture(iAudioFFT, vec2(i, 0.75)).y*pow(i+.5,.9);
	}
	
	colorize = normalize(colorize);
	
	float offset = best;
	
	float osc = texture(iAudioFFT, vec2(offset+tuv.x*.4 +.1, 0.25)).x-.5;
	osc += texture(iAudioFFT, vec2(offset+tuv.x*.4 -.01, 0.25)).x-.5;
	osc += texture(iAudioFFT, vec2(offset+tuv.x*.4 +.01, 0.25)).x-.5;
	osc*=.333;
	float boost = texture(iAudioFFT,vec2(.0)).x;
	float power = pow(boost,2.0);
	
	vec3 color = vec3(.0);
	
	//color += colorize*vec3((power*.9+.1)*0.02/(abs((power*1.4+.2)*osc-uv.y)));
	//color += colorize*vec3((power*.9+.1)*0.02/(abs((power*1.4+.2)*osc-uv.y)),osc*power,osc*boost);
	color += colorize*vec3((power*.9+.1)*0.02/(abs((power*1.4+.2)*osc-uv.y)),osc*power,osc*boost);
	color += colorize*.2*((1.0-power)*.9+.1);
	
	vec2 buv = uv*(1.0+power*power*power*.25);
	//buv.y+=s(power)/10.;
	//was drifting to much away
	//buv += vec2(pow(power,12.0)*.1,iTime*.05);
	
	vec2 blocks = mod(buv,vec2(.1))-vec2(.05);
	vec2 blocksid = sin((buv - mod(buv,vec2(.1)))*412.07);
	float blockint = texture(iAudioFFT,blocksid,-48.0).y;
	float oint = blockint = 
		-    texture(iAudioFFT, vec2(blockint-.02, 0.75)).x
		+2.0*texture(iAudioFFT, vec2(blockint, 0.75)).x
		-    texture(iAudioFFT, vec2(blockint+.02, 0.75)).x;
	blockint = pow(blockint*blockint,2.80)*111.0;
	//blockint = 1.0;
	color += +2.0*blockint*max(.0,min(1.0,(.04+oint*0.05-max(abs(blocks.x),abs(blocks.y)))*500.0))*colorize;
	
		
	color -= length(uv)*.1;
	
	
	//color += texture(iAudioFFT,fragCoord.xy/256.0).xyz*.01;
	color += texture(iAudioFFT,fragCoord.xy/256.0).xyz*.01;
	color = pow(max(vec3(.0),color),vec3(.6));
	
	
	fragColor = vec4(color,1.0);

	#ifdef VIDEO
			vec4 vid = texture(iChannel0, buv);
			//fragColor+=vid;

			fragColor *= vec4(texture(iChannel0,(gl_FragCoord.xy / iResolution.xy)).rgb, .1);

			//tuv.x -=.5;
			tuv.x -=.25;
			tuv.y-=.20;
			//tuv*=best_acc/10.;
			//tuv/=best_acc/10.;
			//tuv/=best*2.;
			/*
			if(tuv.x>-0.135 && tuv.x <.1 && tuv.y <.1){
					vid = texture(iChannel0, .5+2.*tuv);
					//fragColor *=vid*(.1+best*2.);
					vec4 greenScreen = vec4(0.,1.,0.,1.);
					vec3 diff = vid.xyz-greenScreen.xyz;
					float fac = smoothstep(.55-.05,.55+.05,dot(diff,diff));

					if(iTime <4.5) {
							fragColor = mix(vid, fragColor, 1.-fac);
							fragColor*=vid;
					}
					else if(iTime>=4.5 && iTime <7.4){
						vec4 greenScreen = vec4(0.,1.,0.,1.);
						vec3 diff = vid.xyz-greenScreen.xyz;
						fragColor+=vid*fac;
					}
					else if(iTime>7.4 && iTime < 11.2) {
							float gray = dot(vid.rgb, vec3(0.2126, 0.7152, 0.0722)); 
							vid = vec4(vec3(gray), vid.a);
							fragColor = mix(vid, fragColor, 1.-fac);
							fragColor *= vid;    
					}
					else{
						if(best>.35 && best < 0.4){
							vec4 greenScreen = vec4(0.,1.,0.,1.);
							vec3 diff = vid.xyz-greenScreen.xyz;
							fragColor+=vid*fac;
						}else if (best >.4) {
							float gray = dot(vid.rgb, vec3(0.2126, 0.7152, 0.0722)); 
							vid = vec4(vec3(gray), vid.a);
							fragColor = mix(vid, fragColor, 1.-fac);
							fragColor *= vid;    
							
						}
						else{
							fragColor = mix(vid, fragColor, 1.-fac);
							fragColor*=vid;
						}
					}
			}
			*/
	#endif	
	/*vec3 col0 = vec3(0.0, 0.0, 2.8);
    vec3 col1 = vec3(sin(iTime)/1.5 + 10.8 * best_acc, 0.3 + 0.2 * best_acc, 0.2 + 0.3 * best_acc) * pow(best_acc, 2.0) * 3.0;
    vec3 col2 = vec3(best_acc, best_acc*2.5, best_acc*5.);
    vec3 col_greenscreen = getTexture(.5+2.*tuv);
    col0 = chromaKey(col_greenscreen, col0);
    col1 = chromaKey(col_greenscreen, col1);
    col2 = chromaKey(col_greenscreen, col2);

	fragColor.xyz *= col2;
	*/	
	
	/*vid.r *=best_acc*10.*sin(iTime/10.);
	vid.g *=best_acc*cos(iTime/5.);;
	vid.b *=best_acc*(.5+sin(iTime/20.));
	*/
	//fragColor *=vid+fragColor;
	
	//fragColor *=vid*10.+fragColor;
	//fragColor +=vid;
}
void main(){
    // Get fragment coordinates with Y-flip for OneOffRender
    vec2 fragCoord = gl_FragCoord.xy;

	mainImage(fragColor, fragCoord);
}
	

