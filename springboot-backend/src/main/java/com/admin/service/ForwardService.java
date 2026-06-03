package com.admin.service;

import com.admin.common.dto.ForwardDto;
import com.admin.common.dto.ForwardUpdateDto;
import com.admin.common.lang.R;
import com.admin.entity.Forward;
import com.baomidou.mybatisplus.extension.service.IService;
import java.util.Map;

/**
 * <p>
 *  服务类
 * </p>
 *
 * @author QAQ
 * @since 2025-06-03
 */
public interface ForwardService extends IService<Forward> {

    /**
     * 创建端口转发
     * @param forwardDto 转发数据
     * @return 结果
     */
    R createForward(ForwardDto forwardDto);

    /**
     * 获取端口转发列表
     * @return 结果
     */
    R getAllForwards();

    /**
     * 更新端口转发
     * @param forwardUpdateDto 更新数据
     * @return 结果
     */
    R updateForward(ForwardUpdateDto forwardUpdateDto);

    /**
     * 删除端口转发
     * @param id 转发ID
     * @return 结果
     */
    R deleteForward(Long id);

    /**
     * 强制删除端口转发
     * 跳过GOST节点验证，直接删除数据库记录
     * @param id 转发ID
     * @return 结果
     */
    R forceDeleteForward(Long id);

    /**
     * 暂停转发服务
     * @param id 转发ID
     * @return 结果
     */
    R pauseForward(Long id);

    /**
     * 恢复转发服务
     * @param id 转发ID
     * @return 结果
     */
    R resumeForward(Long id);

    /**
     * 转发诊断功能
     * @param id 转发ID
     * @return 诊断结果
     */
    R diagnoseForward(Long id);

    /**
     * 更新转发排序
     * @param params 包含forwards数组的参数
     * @return 更新结果
     */
    R updateForwardOrder(Map<String, Object> params);

    /**
     * 同步所有转发规则到对应的节点
     * 用于场景：节点重连后、手动触发全量同步
     * @return 同步结果
     */
    R syncAllForwards();

    /**
     * 同步指定节点的所有转发规则
     * 当节点 WebSocket 重连时自动调用
     * @param nodeId 节点ID
     * @return 同步结果
     */
    R syncNodeForwards(Long nodeId);

    void updateForwardA(Forward forward);
}
