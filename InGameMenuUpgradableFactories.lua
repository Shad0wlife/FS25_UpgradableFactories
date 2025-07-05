InGameMenuUpgradableFactories = {
}

function InGameMenuUpgradableFactories.initialize()
    InGameMenuProductionFrame.updateMenuButtons = Utils.appendedFunction(InGameMenuProductionFrame.updateMenuButtons, InGameMenuUpgradableFactories.updateMenuButtons)
end

function InGameMenuUpgradableFactories:onButtonUpgrade()
    if self.pageProduction == nil then
        UFInfo("No page to get the selected production from is known.")
    end

    local _, prodpoint = self.pageProduction:getSelectedProduction()
    local money = g_farmManager:getFarmById(g_currentMission:getFarmId()):getBalance()
    UFInfo(
        "Request upgrade %s to level %d of %d [cost: %s | money: %s]",
        prodpoint.owningPlaceable:getName(),
        prodpoint.productionLevel,
        UpgradableFactories.MAX_LEVEL,
        g_i18n:formatMoney(prodpoint.owningPlaceable.upgradePrice),
        g_i18n:formatMoney(money)
    )

    if prodpoint.productionLevel >= UpgradableFactories.MAX_LEVEL then
        InfoDialog.show(
            g_i18n:getText("uf_max_level")
        )
        UFInfo("Production already at max level")
    elseif money >= prodpoint.owningPlaceable.upgradePrice then
        local text = string.format(
            g_i18n:getText("uf_upgrade_dialog"),
            prodpoint.owningPlaceable:getName(),
            prodpoint.productionLevel+1,
            g_i18n:formatMoney(prodpoint.owningPlaceable.upgradePrice)
        )
        YesNoDialog.show(
            InGameMenuUpgradableFactories.onUpgradeConfirm,
            InGameMenuUpgradableFactories,
            text,
            --TODO: Translate this
            "Upgrade Factory?",
            g_i18n:getText("button_yes"),
            g_i18n:getText("button_no"),
            nil, --dialogType
            nil, --yesSound
            nil, --noSound
            prodpoint
        )
    else
        InfoDialog.show(
            g_i18n:getText(ShopConfigScreen.L10N_SYMBOL.NOT_ENOUGH_MONEY_BUY)
        )
        UFInfo("Not enough money")
    end
end

function InGameMenuUpgradableFactories.onListSelectionChanged(pageProduction, list, section, index)
    local prodpoints = pageProduction:getProductionPoints()
    if #prodpoints > 0 then
        local prodpoint = prodpoints[section]
        pageProduction.upgradeButtonInfo.disabled = prodpoint == nil or not prodpoint.isUpgradable
        pageProduction:setMenuButtonInfoDirty()
    end
end

--Needs self since identity is passed as the target of the callback
function InGameMenuUpgradableFactories:onUpgradeConfirm(confirm, prodpoint)
    if confirm then
        -- Send event, the actual buying/money change needs to be done by the server
        UpdateProductionEvent.sendEvent(prodpoint)
        
        UFInfo("Upgrade confirmed")
    else
        UFInfo("Upgrade canceled")
    end
end

function InGameMenuUpgradableFactories:refreshProductionPage()
    if self.pageProduction.pointsList ~= nil and self.pageProduction.chainManager ~= nil then
        self.pageProduction.pointsList:reloadData()
    else
        UFInfo("Nil check on production point list refresh failed.")
    end
end

function InGameMenuUpgradableFactories.updateMenuButtons(prodPage, superFunc)
    if prodPage ~= nil then
        InGameMenuUpgradableFactories.pageProduction = prodPage
        local upgradeButtonInfo = {
            profile = "buttonOK",
            inputAction = InputAction.MENU_EXTRA_1,
            text = g_i18n:getText("uf_upgrade"),
            callback = InGameMenuUpgradableFactories.onButtonUpgrade
        }

        if prodPage.pointsSelector:getState() == InGameMenuProductionFrame.POINTS_OWNED then
            if g_currentMission:getHasPlayerPermission("manageProductions") then
                local production, productionPoint = prodPage:getSelectedProduction()
                if productionPoint ~= nil then
                    table.insert(prodPage.menuButtonInfo, upgradeButtonInfo)
                end
            end
        end
    end
end