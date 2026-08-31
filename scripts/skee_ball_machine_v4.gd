class_name SkeeBallMachineV4
extends SkeeBallMachineV3

# Ratios measured directly from the user-supplied tabletop STL package.
# Reference ball = 19 mm. Gameplay ball = 3 in. The STL is not a runtime asset.
const S := (3.0 * INCH) / 19.0
const FW := 154.0 * S
const FL := 200.0 * S
const HW := 160.0 * S
const BT := 10.0 * S
const HR := 12.5 * S
const RH := 30.0 * S
const WT := 1.75 * S
const UWT := 1.1421 * S
const SEG := 128
const FB := Vector3(0.0, 0.6600, HOP_END_Z - 0.0005)
const FV := Vector3(0.0, 0.70710678, -0.70710678)
const FN := Vector3(0.0, 0.70710678, 0.70710678)

# Seven physical drain centers, measured from the bottom of skeeball-face.stl.
const H10 := 41.0 * S
const H20 := 71.0 * S
const H30 := 99.0 * S
const H40 := 142.0 * S
const H50 := 177.0 * S
const H100 := 182.0 * S
const X100 := 55.0 * S

# U and ring/cup cross-sections measured from the STL.
const UC := 100.9973 * S
const UR := 74.4333 * S
const UTOP := 191.0 * S
const C20 := 108.9973 * S
const R20 := 51.875 * S
const C30 := 105.4973 * S
const R30R := 20.125 * S
const C40 := 143.4973 * S
const R40R := 15.375 * S
const C50 := 177.9973 * S
const R50R := 14.875 * S
const C100 := 181.9973 * S
const R100R := 13.875 * S
const LIFT := 0.020 * INCH

func _build_materials() -> void:
    super._build_materials()
    target_material.albedo_color = Color(0.18, 0.07, 0.04)
    target_material.roughness = 0.97
    hole_material.albedo_color = Color(0.94, 0.93, 0.89)
    hole_material.roughness = 0.88
    target_physics_material.friction = 0.80
    target_physics_material.bounce = 0.025

func _target_point(u: float, v: float, n: float = 0.0) -> Vector3:
    return FB + Vector3.RIGHT * u + FV * v + FN * n

func _targets() -> Array[Dictionary]:
    return [
        {"p":10,"u":0.0,"v":H10,"id":"10"}, {"p":20,"u":0.0,"v":H20,"id":"20"},
        {"p":30,"u":0.0,"v":H30,"id":"30"}, {"p":40,"u":0.0,"v":H40,"id":"40"},
        {"p":50,"u":0.0,"v":H50,"id":"50"}, {"p":100,"u":-X100,"v":H100,"id":"100L"},
        {"p":100,"u":X100,"v":H100,"id":"100R"}
    ]

func _build_playfield_cabinet() -> void:
    var front := ALLEY_REAR_Z + 0.10
    var depth := PLAYFIELD_DEPTH
    var cz := front - depth * 0.5
    var t := 0.040
    var x := HW * 0.5 - t * 0.5
    _add_static_box("HeadLeftSide", Vector3(t, OVERALL_HEIGHT, depth), Vector3(-x, OVERALL_HEIGHT*0.5, cz), cabinet_material)
    _add_static_box("HeadRightSide", Vector3(t, OVERALL_HEIGHT, depth), Vector3(x, OVERALL_HEIGHT*0.5, cz), cabinet_material)
    _add_static_box("HeadBack", Vector3(HW, OVERALL_HEIGHT, 0.050), Vector3(0.0, OVERALL_HEIGHT*0.5, BACK_Z+0.025), cabinet_material)

func _build_target_board() -> void:
    _board()
    _rear()
    _u()
    _ring("Target20",0.0,C20,R20,WT)
    _ring("Target30",0.0,C30,R30R,WT)
    _ring("Target40",0.0,C40,R40R,WT)
    _ring("Target50",0.0,C50,R50R,WT)
    _ring("Target100L",-X100,C100,R100R,WT)
    _ring("Target100R",X100,C100,R100R,WT)
    _label("Label10",10,0.0,UC-UR)
    _label("Label20",20,0.0,C20-R20)
    _label("Label30",30,0.0,C30-R30R)
    _label("Label40",40,0.0,C40-R40R)
    _label("Label50",50,0.0,C50-R50R)
    _label("Label100L",100,-X100,C100-R100R)
    _label("Label100R",100,X100,C100-R100R)
    for t in _targets():
        _throat("Drain_%s" % String(t["id"]), float(t["u"]), float(t["v"]))
        _sensor(int(t["p"]), float(t["u"]), float(t["v"]))

func _board() -> void:
    var f := Node3D.new(); f.name="TargetBoardFrame"
    f.position=_target_point(0.0,FL*0.5,-BT*0.5); f.basis=Basis(Vector3.RIGHT,FN,FV).orthonormalized(); add_child(f)
    var c:=CSGCombiner3D.new(); c.name="SevenHoleBoard"; c.use_collision=true; c.collision_layer=1; c.collision_mask=1; f.add_child(c)
    var p:=CSGBox3D.new(); p.size=Vector3(FW,BT,FL); p.material=target_material; c.add_child(p)
    for t in _targets():
        var h:=CSGCylinder3D.new(); h.radius=HR; h.height=BT*3.0; h.sides=SEG; h.smooth_faces=true
        h.operation=CSGShape3D.OPERATION_SUBTRACTION; h.position=Vector3(float(t["u"]),0.0,float(t["v"])-FL*0.5); c.add_child(h)

func _rear() -> void:
    _add_oriented_visual_box("DropBack",Vector3(FW,0.010,FL),_target_point(0.0,FL*0.5,-35.0*S),Basis(Vector3.RIGHT,FN,FV).orthonormalized(),hole_void_material)

func _u() -> void:
    var f:=Node3D.new(); f.name="Target10UFrame"; f.position=_target_point(0.0,UC,LIFT); f.basis=Basis(Vector3.RIGHT,FN,FV).orthonormalized(); add_child(f)
    var c:=CSGCombiner3D.new(); c.name="Target10U"; c.use_collision=true; c.collision_layer=1; c.collision_mask=1; f.add_child(c)
    var o:=CSGCylinder3D.new(); o.radius=UR+UWT*0.5; o.height=RH; o.sides=SEG; o.smooth_faces=true; o.material=hole_material; o.position.y=RH*0.5; c.add_child(o)
    var i:=CSGCylinder3D.new(); i.radius=UR-UWT*0.5; i.height=RH+0.006; i.sides=SEG; i.smooth_faces=true; i.operation=CSGShape3D.OPERATION_SUBTRACTION; i.position.y=RH*0.5; c.add_child(i)
    var cut:=CSGBox3D.new(); cut.size=Vector3(UR*2.2,RH+0.012,UR*2.2); cut.position=Vector3(0.0,RH*0.5,UR+UWT); cut.operation=CSGShape3D.OPERATION_SUBTRACTION; c.add_child(cut)
    var ll:=UTOP-UC
    for side in [-1.0,1.0]:
        var leg:=CSGBox3D.new(); leg.size=Vector3(UWT,RH,ll+UWT); leg.position=Vector3(side*UR,RH*0.5,ll*0.5); leg.material=hole_material; c.add_child(leg)

func _ring(name:String,u:float,v:float,r:float,w:float) -> void:
    var f:=Node3D.new(); f.name=name+"Frame"; f.position=_target_point(u,v,LIFT); f.basis=Basis(Vector3.RIGHT,FN,FV).orthonormalized(); add_child(f)
    var c:=CSGCombiner3D.new(); c.name=name; c.use_collision=true; c.collision_layer=1; c.collision_mask=1; f.add_child(c)
    var o:=CSGCylinder3D.new(); o.radius=r+w*0.5; o.height=RH; o.sides=SEG; o.smooth_faces=true; o.material=hole_material; o.position.y=RH*0.5; c.add_child(o)
    var i:=CSGCylinder3D.new(); i.radius=r-w*0.5; i.height=RH+0.006; i.sides=SEG; i.smooth_faces=true; i.operation=CSGShape3D.OPERATION_SUBTRACTION; i.position.y=RH*0.5; c.add_child(i)

func _throat(name:String,u:float,v:float) -> void:
    var tw:=1.5*S
    var f:=Node3D.new(); f.name=name+"Frame"; f.position=_target_point(u,v,-BT); f.basis=Basis(Vector3.RIGHT,FN,FV).orthonormalized(); add_child(f)
    var c:=CSGCombiner3D.new(); c.name=name; c.use_collision=true; c.collision_layer=1; c.collision_mask=1; f.add_child(c)
    var o:=CSGCylinder3D.new(); o.radius=HR+tw; o.height=BT; o.sides=SEG; o.smooth_faces=true; o.material=hole_material; o.position.y=BT*0.5; c.add_child(o)
    var i:=CSGCylinder3D.new(); i.radius=HR; i.height=BT+0.006; i.sides=SEG; i.smooth_faces=true; i.operation=CSGShape3D.OPERATION_SUBTRACTION; i.position.y=BT*0.5; c.add_child(i)

func _sensor(points:int,u:float,v:float) -> void:
    var a:=Area3D.new(); a.name="ScoreReset_%d"%points; a.position=_target_point(u,v,-0.006); a.basis=Basis(Vector3.RIGHT,FN,FV).orthonormalized(); a.collision_layer=0; a.collision_mask=1; a.monitoring=true; add_child(a)
    var cs:=CollisionShape3D.new(); var sh:=CylinderShape3D.new(); sh.radius=HR*0.96; sh.height=0.024; cs.shape=sh; a.add_child(cs); a.body_entered.connect(_on_score_reset_entered.bind(points))

func _label(name:String,points:int,u:float,v:float) -> void:
    var l:=Label3D.new(); l.name=name; l.text=str(points); l.font_size=54 if points<100 else 46; l.pixel_size=0.00125; l.modulate=Color(0.08,0.055,0.04); l.outline_size=0
    l.position=_target_point(u,v,RH*0.55); l.basis=Basis(Vector3.RIGHT,FN,-FV).orthonormalized(); add_child(l)

func _build_backboard() -> void:
    var y:=1.82
    _add_static_box("Backboard",Vector3(HW,0.50,0.055),Vector3(0.0,1.60,BACK_Z+0.060),blue_material)
    _add_visual_box("Marquee",Vector3(HW,0.42,0.065),Vector3(0.0,y,BACK_Z+0.078),blue_material)
    _add_visual_box("MarqueeTopTrim",Vector3(HW,0.040,0.075),Vector3(0.0,y+0.23,BACK_Z+0.085),gold_material)
    var title:=Label3D.new(); title.text="SLOT BALL"; title.font_size=72; title.pixel_size=0.0018; title.modulate=Color(0.95,0.72,0.16); title.outline_size=6; title.outline_modulate=Color(0.32,0.055,0.035); title.position=Vector3(0.0,y,BACK_Z+0.118); add_child(title)
