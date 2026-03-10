from seed_demo import DEMO_RECIPE


def test_demo_recipe_has_seven_steps():
    assert len(DEMO_RECIPE["steps"]) == 7


def test_each_step_has_guide_image_prompt():
    for step in DEMO_RECIPE["steps"]:
        assert "guide_image_prompt" in step, f"Step {step['step_number']} missing guide_image_prompt"


def test_p1_conflict_at_steps_3_and_4():
    step3 = DEMO_RECIPE["steps"][2]
    step4 = DEMO_RECIPE["steps"][3]
    assert step3.get("is_parallel") is True or step4.get("is_parallel") is True


def test_recipe_has_checklist_gate():
    assert "checklist_gate" in DEMO_RECIPE
    assert isinstance(DEMO_RECIPE["checklist_gate"], list)
    assert len(DEMO_RECIPE["checklist_gate"]) > 0
