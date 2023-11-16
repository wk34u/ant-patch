#include "default/inputs_define.sh"

$input 	a_position INPUT_NORMAL INPUT_TANGENT INPUT_INDICES INPUT_WEIGHT

#include <bgfx_shader.sh>

#include "common/transform.sh"

uniform vec4 u_outlinescale;
#define u_outline_width u_outlinescale.x

float calc_pixel_width(float clipw)
{
#ifdef FIX_WIDTH
	return 0.01;
#else
	//u_viewRect.z = viewport width
	//u_proj[0][0] = 2.0*near / (right - left)
	// 1.0/(u_viewRect.z * u_proj[0][0]) ==> 1.0/vp_width*(2.0*near/(right-left))
	//	==> (right-left) / (vp_width*2.0*near) ==> ((right-left)/vp_width) * 1.0/(2.0*near)
	// A = (right-left)/vp_width), B = 1.0/(2.0*near)
	// ratio = A*B, where A mean: projection plane width with how many viewport width
	float pixelWidthRatio	= 1.0/(u_viewRect.z * u_proj[0][0]);
	return clipw * pixelWidthRatio;
#endif

}

vec2 calc_offset(vec2 dir, float aspect, float w)
{
	vec2 normal = normalize(vec2(-dir.y, dir.x));
	normal.x /= aspect;
	normal *= 0.5 * w;

    return normal;
}

void main()
{
#	if PACK_TANGENT_TO_QUAT
	mediump vec3 normal = quat_to_normal(a_tangent);
#	else //!PACK_TANGENT_TO_QUAT
	mediump vec3 normal = a_normal;
#	endif//PACK_TANGENT_TO_QUAT

    VSInput vs_input = (VSInput)0;
    #include "default/vs_inputs_getter.sh"
    mediump mat4 wm = get_world_matrix(vsinput.a_indices, vsinput.a_weight);

#ifdef VIEW_SPACE
    mat4 modelView = mul(u_view, wm);
    vec4 pos = mul(modelView, vec4(a_position, 1.0));

    float aspect = u_proj[1][1]/u_proj[0][0];
    // normal should be transformed corredctly by transpose of inverse modelview matrix when anti-uniform scaled
    vec3 normalVS	= normalize(mul(modelView, mediump vec4(normal, 0.0)).xyz);
    normalVS.x *= aspect;
    pos.xyz = pos.xyz + normalVS * u_outline_width;
    gl_Position = mul(u_proj, pos); 
#else // SCREEN_SPACE
    
    float aspect = u_viewRect.w / u_viewRect.z;
    mat4 mvp = mul(u_viewProj, wm);
    vec4 posCS = mul(mvp, vec4(a_position, 1.0));
    vec3 normalCS = normalize(mul(mvp, vec4(normal, 0.0)).xyz);

    normalCS.x *= aspect;

    posCS.xy += 0.01 * u_outline_width * normalCS.xy * posCS.w;
    gl_Position = posCS;
#endif //VIEW_SPACE
}