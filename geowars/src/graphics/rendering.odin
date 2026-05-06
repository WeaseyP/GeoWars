package graphics

import sg "../vendor/sokol/gfx"
import "core:fmt"
import "core:math"
import shared "../shared"

init_rendering :: proc() {
    shared.state.pass_action = {colors = {0={load_action = .DONTCARE}}}
    vertices := [?]f32 { -1,-1,0,0,0,0,0, 1,-1,0,1,0,0,0, -1,1,0,0,1,0,0, 1,1,0,1,1,0,0 }
    shared.state.bind.vertex_buffers[0] = sg.make_buffer({ label="shared-quad-vertices", data=sg.Range{ptr=&vertices[0], size=size_of(vertices)}})
    
    particle_quad_verts := [?]f32{ -0.5,-0.5,0,0, 0.5,-0.5,1,0, -0.5,0.5,0,1, 0.5,0.5,1,1 }
    shared.state.particle_quad_vbo = sg.make_buffer({ label="particle-quad-base", data=sg.Range{ptr=&particle_quad_verts[0], size=size_of(particle_quad_verts)}})
    shared.state.particle_instance_vbo = sg.make_buffer({ label="particle-inst", size=shared.MAX_PARTICLES*size_of(shared.Particle_Instance_Data), type=.VERTEXBUFFER, usage=.STREAM })
    
    shared.state.enemy_instance_vbo = sg.make_buffer({ label="enemy-inst", size=shared.MAX_ENEMIES*size_of(shared.Enemy_Instance_Data), type=.VERTEXBUFFER, usage=.STREAM })
    shared.state.blackhole_instance_vbo = sg.make_buffer({ label="blackhole-inst", size=shared.MAX_BLACKHOLES*size_of(shared.Blackhole_Instance_Data), type=.VERTEXBUFFER, usage=.STREAM })


    bg_shd := sg.make_shader(shared.bg_shader_desc(sg.query_backend()))
    player_shd := sg.make_shader(shared.player_shader_desc(sg.query_backend()))
    particle_shd := sg.make_shader(shared.particle_shader_desc(sg.query_backend()))
    enemy_shd := sg.make_shader(shared.enemy_shader_desc(sg.query_backend())) 
    blackhole_shd := sg.make_shader(shared.blackhole_shader_desc(sg.query_backend()))

    shared.state.bg_pip = sg.make_pipeline({ label="bg-pip", shader=bg_shd, layout={buffers={0={stride=shared.vertex_stride}},attrs={shared.ATTR_bg_position={format=.FLOAT2}}}, primitive_type=.TRIANGLE_STRIP})
    shared.state.player_pip = sg.make_pipeline({ label="player-pip", shader=player_shd, layout={buffers={0={stride=shared.vertex_stride}},attrs={shared.ATTR_player_position={format=.FLOAT2}}}, primitive_type=.TRIANGLE_STRIP, colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA,dst_factor_rgb=.ONE_MINUS_SRC_ALPHA}}}, depth={write_enabled=false, compare=.ALWAYS} })
    
    shared.state.particle_pip = sg.make_pipeline({ label="particle-pip", shader=particle_shd,
        layout={ buffers={0={stride=shared.particle_quad_stride,step_func=.PER_VERTEX}, 1={stride=size_of(shared.Particle_Instance_Data),step_func=.PER_INSTANCE}}, 
              attrs={shared.ATTR_particle_quad_pos={buffer_index=0,offset=0,format=.FLOAT2}, shared.ATTR_particle_quad_uv={buffer_index=0,offset=8,format=.FLOAT2},
                     shared.ATTR_particle_instance_pos_size_rot={buffer_index=1,offset=0,format=.FLOAT4}, shared.ATTR_particle_instance_color={buffer_index=1,offset=16,format=.FLOAT4}} },
        primitive_type=.TRIANGLE_STRIP, colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA, dst_factor_rgb=.ONE}}}, depth={write_enabled=false, compare=.ALWAYS}
    })
    if sg.query_pipeline_state(shared.state.particle_pip) != .VALID { fmt.eprintf("!!! CRITICAL: Particle pipeline creation failed!\n"); }

    shared.state.blackhole_pip = sg.make_pipeline({ label="blackhole-pip", shader=blackhole_shd,
        layout={ buffers={0={stride=shared.blackhole_quad_stride,step_func=.PER_VERTEX}, 1={stride=size_of(shared.Blackhole_Instance_Data),step_func=.PER_INSTANCE}}, 
              attrs={shared.ATTR_blackhole_quad_pos={buffer_index=0,offset=0,format=.FLOAT2}, shared.ATTR_blackhole_quad_uv={buffer_index=0,offset=8,format=.FLOAT2},
                     shared.ATTR_blackhole_instance_pos_size_rot={buffer_index=1,offset=0,format=.FLOAT4}, shared.ATTR_blackhole_instance_color={buffer_index=1,offset=16,format=.FLOAT4}} },
        primitive_type=.TRIANGLE_STRIP, colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA, dst_factor_rgb=.ONE_MINUS_SRC_ALPHA}}}, depth={write_enabled=false, compare=.ALWAYS} 
    })
    if sg.query_pipeline_state(shared.state.blackhole_pip) != .VALID { fmt.eprintf("!!! CRITICAL: Blackhole pipeline creation failed!\n"); }
    else { fmt.printf("--- Blackhole pipeline created successfully ---\n"); }


    shared.state.enemy_pip = sg.make_pipeline({ 
        label="enemy-pip", 
        shader=enemy_shd,
        layout={ 
            buffers={
                0={stride=shared.enemy_quad_stride, step_func=.PER_VERTEX},
                1={stride=size_of(shared.Enemy_Instance_Data), step_func=.PER_INSTANCE}
            },
            attrs={ 
                shared.ATTR_enemy_quad_pos_in={buffer_index=0,offset=0,format=.FLOAT2},
                shared.ATTR_enemy_quad_uv_in={buffer_index=0,offset=8,format=.FLOAT2},
                shared.ATTR_enemy_instance_pos_vs_in={buffer_index=1,offset=0,format=.FLOAT2},
                shared.ATTR_enemy_instance_main_rotation_vs_in={buffer_index=1,offset=8,format=.FLOAT},
                shared.ATTR_enemy_instance_visual_scale_vs_in={buffer_index=1,offset=12,format=.FLOAT},
                shared.ATTR_enemy_instance_color_vs_in={buffer_index=1,offset=16,format=.FLOAT4},
                shared.ATTR_enemy_instance_effect_params_vs_in={buffer_index=1,offset=32,format=.FLOAT4},
                shared.ATTR_enemy_instance_enemy_type_vs_in={buffer_index=1,offset=48,format=.FLOAT},
            }
        },
        primitive_type=.TRIANGLE_STRIP, 
        colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA, dst_factor_rgb=.ONE_MINUS_SRC_ALPHA}}}, 
        depth={write_enabled=false, compare=.ALWAYS}
    })
    if sg.query_pipeline_state(shared.state.enemy_pip) != .VALID { fmt.eprintf("!!! CRITICAL: Enemy pipeline creation failed!\n"); }

    shared.state.particle_bind = sg.Bindings{ vertex_buffers = { 0=shared.state.particle_quad_vbo, 1=shared.state.particle_instance_vbo } }
    shared.state.enemy_bind = sg.Bindings{ vertex_buffers = { 0=shared.state.particle_quad_vbo, 1=shared.state.enemy_instance_vbo } } 
    shared.state.blackhole_bind = sg.Bindings{ vertex_buffers = {0=shared.state.particle_quad_vbo, 1=shared.state.blackhole_instance_vbo } }
}
