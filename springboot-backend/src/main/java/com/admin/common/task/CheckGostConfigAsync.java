package com.admin.common.task;

import com.admin.common.dto.ConfigItem;
import com.admin.common.dto.GostConfigDto;
import com.admin.common.dto.GostDto;
import com.admin.common.dto.SpeedLimitUpdateDto;
import com.admin.common.utils.GostUtil;
import com.admin.entity.Forward;
import com.admin.entity.Node;
import com.admin.entity.SpeedLimit;
import com.admin.entity.Tunnel;
import com.admin.entity.UserTunnel;
import com.admin.service.ForwardService;
import com.admin.service.NodeService;
import com.admin.service.SpeedLimitService;
import com.admin.service.TunnelService;
import com.admin.service.UserTunnelService;
import com.alibaba.fastjson.JSONObject;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Lazy;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

@Slf4j
@Service
public class CheckGostConfigAsync {

    @Resource
    private NodeService nodeService;

    @Resource
    @Lazy
    private ForwardService forwardService;

    @Resource
    @Lazy
    private SpeedLimitService speedLimitService;

    @Resource
    @Lazy
    private TunnelService tunnelService;

    @Resource
    private UserTunnelService userTunnelService;

    /**
     * 清理孤儿配置，并补齐数据库中存在但节点缺失的配置。
     */
    @Async
    public void cleanNodeConfigs(String node_id, GostConfigDto gostConfig) {
        System.out.println(JSONObject.toJSONString(gostConfig));
        Node node = nodeService.getById(node_id);
        if (node == null) {
            return;
        }

        cleanOrphanedServices(gostConfig, node);
        cleanOrphanedChains(gostConfig, node);
        cleanOrphanedLimiters(gostConfig, node);
        syncLimiters(gostConfig, node);
        syncForwardConfigs(gostConfig, node);
    }

    /**
     * 清理节点上数据库已不存在的 service。
     */
    private void cleanOrphanedServices(GostConfigDto gostConfig, Node node) {
        if (gostConfig.getServices() == null) {
            return;
        }

        for (ConfigItem service : gostConfig.getServices()) {
            safeExecute(() -> {
                if (Objects.equals(service.getName(), "web_api")) {
                    return;
                }

                String[] serviceIds = parseServiceName(service.getName());
                if (serviceIds.length != 4) {
                    return;
                }

                String forwardId = serviceIds[0];
                String userId = serviceIds[1];
                String userTunnelId = serviceIds[2];
                String type = serviceIds[3];

                Forward forward = forwardService.getById(forwardId);
                if (forward != null) {
                    return;
                }

                if (Objects.equals(type, "tcp")) {
                    log.info("删除孤立服务 {} (节点: {})", service.getName(), node.getId());
                    GostDto gostDto = GostUtil.DeleteService(node.getId(), forwardId + "_" + userId + "_" + userTunnelId);
                    System.out.println(gostDto);
                }

                if (Objects.equals(type, "tls")) {
                    log.info("删除孤立服务 {} (节点: {})", service.getName(), node.getId());
                    GostUtil.DeleteRemoteService(node.getId(), forwardId + "_" + userId + "_" + userTunnelId);
                }
            }, "清理服务 " + service.getName());
        }
    }

    /**
     * 清理节点上数据库已不存在的 chain。
     */
    private void cleanOrphanedChains(GostConfigDto gostConfig, Node node) {
        if (gostConfig.getChains() == null) {
            return;
        }

        for (ConfigItem chain : gostConfig.getChains()) {
            safeExecute(() -> {
                String[] serviceIds = parseServiceName(chain.getName());
                if (serviceIds.length != 4) {
                    return;
                }

                String forwardId = serviceIds[0];
                String userId = serviceIds[1];
                String userTunnelId = serviceIds[2];
                String type = serviceIds[3];

                if (!Objects.equals(type, "chains")) {
                    return;
                }

                Forward forward = forwardService.getById(forwardId);
                if (forward == null) {
                    log.info("删除孤立链 {} (节点: {})", chain.getName(), node.getId());
                    GostUtil.DeleteChains(node.getId(), forwardId + "_" + userId + "_" + userTunnelId);
                }
            }, "清理链 " + chain.getName());
        }
    }

    /**
     * 清理节点上数据库已不存在的 limiter。
     */
    private void cleanOrphanedLimiters(GostConfigDto gostConfig, Node node) {
        if (gostConfig.getLimiters() == null) {
            return;
        }

        for (ConfigItem limiter : gostConfig.getLimiters()) {
            safeExecute(() -> {
                SpeedLimit speedLimit = speedLimitService.getById(limiter.getName());
                if (speedLimit == null) {
                    log.info("删除孤立限速器 {} (节点: {})", limiter.getName(), node.getId());
                    GostUtil.DeleteLimiters(node.getId(), Long.parseLong(limiter.getName()));
                }
            }, "清理限速器 " + limiter.getName());
        }
    }

    /**
     * 同步节点缺失的 limiter。
     */
    private void syncLimiters(GostConfigDto gostConfig, Node node) {
        List<Tunnel> tunnelList = tunnelService.list(new QueryWrapper<Tunnel>().eq("in_node_id", node.getId()));
        if (tunnelList == null || tunnelList.isEmpty()) {
            return;
        }

        safeExecute(() -> {
            List<Long> tunnelIds = new ArrayList<>();
            for (Tunnel tunnel : tunnelList) {
                tunnelIds.add(tunnel.getId());
            }

            List<SpeedLimit> speedLimits = speedLimitService.list(new QueryWrapper<SpeedLimit>().in("tunnel_id", tunnelIds));
            if (speedLimits == null || speedLimits.isEmpty()) {
                return;
            }

            List<Long> limiterIdsOnNode = new ArrayList<>();
            if (gostConfig.getLimiters() != null) {
                for (ConfigItem limiter : gostConfig.getLimiters()) {
                    limiterIdsOnNode.add(Long.valueOf(limiter.getName()));
                }
            }

            for (SpeedLimit speedLimit : speedLimits) {
                if (limiterIdsOnNode.contains(speedLimit.getId())) {
                    continue;
                }

                SpeedLimitUpdateDto dto = new SpeedLimitUpdateDto();
                dto.setId(speedLimit.getId());
                dto.setName(speedLimit.getName());
                dto.setSpeed(speedLimit.getSpeed());
                dto.setTunnelId(speedLimit.getTunnelId());
                dto.setTunnelName(speedLimit.getTunnelName());
                speedLimitService.updateSpeedLimit(dto);
            }
        }, "同步限速器");
    }

    /**
     * 同步节点缺失的转发配置。
     * 迁移后节点通常是空配置，这里会把数据库中的活动转发重新下发。
     */
    private void syncForwardConfigs(GostConfigDto gostConfig, Node node) {
        safeExecute(() -> {
            List<Tunnel> relatedTunnels = tunnelService.list(
                    new QueryWrapper<Tunnel>()
                            .eq("in_node_id", node.getId())
                            .or()
                            .eq("out_node_id", node.getId())
            );
            if (relatedTunnels == null || relatedTunnels.isEmpty()) {
                return;
            }

            Map<Long, Tunnel> tunnelMap = new HashMap<>();
            List<Long> tunnelIds = new ArrayList<>();
            for (Tunnel tunnel : relatedTunnels) {
                tunnelMap.put(tunnel.getId(), tunnel);
                tunnelIds.add(tunnel.getId());
            }

            List<Forward> forwards = forwardService.list(
                    new QueryWrapper<Forward>()
                            .in("tunnel_id", tunnelIds)
                            .eq("status", 1)
            );
            if (forwards == null || forwards.isEmpty()) {
                return;
            }

            Set<String> existingServices = new HashSet<>();
            if (gostConfig.getServices() != null) {
                for (ConfigItem service : gostConfig.getServices()) {
                    existingServices.add(service.getName());
                }
            }

            Set<String> existingChains = new HashSet<>();
            if (gostConfig.getChains() != null) {
                for (ConfigItem chain : gostConfig.getChains()) {
                    existingChains.add(chain.getName());
                }
            }

            for (Forward forward : forwards) {
                Tunnel tunnel = tunnelMap.get(Long.valueOf(forward.getTunnelId()));
                if (tunnel == null) {
                    continue;
                }

                if (!needsForwardSync(forward, tunnel, node, existingServices, existingChains)) {
                    continue;
                }

                log.info("节点 {} 缺少转发 {}({}) 配置，开始自动补发", node.getId(), forward.getId(), forward.getName());
                forwardService.updateForwardA(forward);
            }
        }, "同步缺失的转发配置");
    }

    private boolean needsForwardSync(
            Forward forward,
            Tunnel tunnel,
            Node node,
            Set<String> existingServices,
            Set<String> existingChains
    ) {
        String baseName = buildBaseServiceName(forward);

        if (Objects.equals(tunnel.getInNodeId(), node.getId())) {
            if (!existingServices.contains(baseName + "_tcp") || !existingServices.contains(baseName + "_udp")) {
                return true;
            }

            if (Objects.equals(tunnel.getType(), 2) && !existingChains.contains(baseName + "_chains")) {
                return true;
            }
        }

        return Objects.equals(tunnel.getType(), 2)
                && Objects.equals(tunnel.getOutNodeId(), node.getId())
                && !existingServices.contains(baseName + "_tls");
    }

    private String buildBaseServiceName(Forward forward) {
        String userTunnelId = "0";
        UserTunnel userTunnel = getUserTunnel(forward.getUserId(), forward.getTunnelId());
        if (userTunnel != null) {
            userTunnelId = String.valueOf(userTunnel.getId());
        }
        return forward.getId() + "_" + forward.getUserId() + "_" + userTunnelId;
    }

    private UserTunnel getUserTunnel(Integer userId, Integer tunnelId) {
        return userTunnelService.getOne(
                new QueryWrapper<UserTunnel>()
                        .eq("user_id", userId)
                        .eq("tunnel_id", tunnelId)
        );
    }

    /**
     * 安全执行，避免单条异常中断整体同步。
     */
    private void safeExecute(Runnable operation, String operationDesc) {
        try {
            operation.run();
        } catch (Exception e) {
            log.info("执行操作失败: {}", operationDesc, e);
        }
    }

    /**
     * 解析服务名称。
     */
    private String[] parseServiceName(String serviceName) {
        return serviceName.split("_");
    }
}
