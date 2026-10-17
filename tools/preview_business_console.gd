extends SceneTree
## 临时验收脚本：在真实店铺宿主里做一杯并交付，抓取业务页截图与文本。

const SHOT_PREFIX := "res://artifacts/console_business_"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var game: MainGame = load("res://src/core/main.tscn").instantiate()
	game.day1_story_enabled = true
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	var state := root.get_node("GameState")
	var tools := game.get_debug_tools()
	var panel := tools.get_panel()
	tools.toggle_panel()
	await process_frame
	var tabs: TabContainer = panel.get_node("Panel/Margin/Tools/Tabs")
	var sections: TabContainer = panel.get_node("Panel/Margin/Tools/Tabs/业务/Sections")
	tabs.current_tab = 3

	state.set_flag("day1.human_open")
	var delivery := game.get_task_delivery()
	print("accept_order=", delivery.accept_order("day1_human"))
	tools.refresh()
	sections.current_tab = 2
	print("=== 接单后 产出 ===")
	print(panel.production_text.text)
	await _shot("01_order_production", sections, 2)
	sections.current_tab = 3
	print("=== 接单后 任务 ===")
	print(panel.task_text.text)
	await _shot("02_order_task", sections, 3)
	sections.current_tab = 4
	print("=== 接单后 Bridge ===")
	print(panel.bridge_text.text)
	await _shot("03_order_bridge", sections, 4)

	var production := game.get_tea_production()
	var order: Dictionary = production.get_order()
	var crafted: Dictionary = production.craft(order.recipe)
	print("craft=", crafted.get("code", ""), " / ", crafted.get("message", ""))
	tools.refresh()
	sections.current_tab = 2
	print("=== 制作后 产出 ===")
	print(panel.production_text.text)
	await _shot("04_after_craft_production", sections, 2)
	sections.current_tab = 1
	print("=== 制作后 仓库 ===")
	print(panel.inventory_text.text)
	await _shot("05_after_craft_inventory", sections, 1)

	var delivered: Dictionary = delivery.deliver_to("human_customer")
	print("deliver=", delivered)
	tools.refresh()
	sections.current_tab = 0
	print("=== 交付后 钱包 ===")
	print(panel.wallet_text.text)
	await _shot("06_after_delivery_wallet", sections, 0)
	sections.current_tab = 3
	print("=== 交付后 任务 ===")
	print(panel.task_text.text)
	await _shot("07_after_delivery_task", sections, 3)
	sections.current_tab = 1
	print("=== 交付后 仓库 ===")
	print(panel.inventory_text.text)
	await _shot("08_after_delivery_inventory", sections, 1)
	quit(0)

func _shot(id: String, sections: TabContainer, section: int) -> void:
	sections.current_tab = section
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s%s.png" % [SHOT_PREFIX, id])
	print("shot: ", id)
